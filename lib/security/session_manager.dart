import 'dart:math';

/// Session lifecycle manager for the Tusker Trailer RRC BLE protocol.
///
/// Responsibilities:
///   • Generate a cryptographically random session ID per authenticated session.
///   • Provide a monotonically increasing outbound sequence counter.
///   • Track inbound sequence numbers in a rolling window for replay detection.
///   • Validate inbound packet timestamps for freshness (anti-replay).
///
/// Thread safety: pure Dart, single-threaded isolate; no concurrent mutation.
class SessionManager {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  // Rolling inbound sequence replay window size.
  static const int _replayWindowSize = 64;

  // Maximum acceptable age for an inbound packet — reject anything older.
  static const int _maxPacketAgeMs = 30000; // 30 seconds

  final Random _rng = Random.secure();

  int  _sessionId    = 0;
  int  _seqCounter   = 0;
  bool _sessionActive = false;

  // Rolling window of recently seen inbound sequence numbers.
  final List<int> _inboundWindow = List.filled(_replayWindowSize, -1);
  int _windowHead = 0;

  bool get isSessionActive => _sessionActive;
  int  get sessionId       => _sessionId;

  /// Begin a new authenticated session.
  ///
  /// Generates a fresh non-zero random session ID and resets all counters.
  /// Must be called before encoding the first auth/control/heartbeat packet.
  void beginSession() {
    _sessionId     = _rng.nextInt(0x7FFFFFFF) + 1; // non-zero, fits uint32
    _seqCounter    = 0;
    _sessionActive = true;
    _inboundWindow.fillRange(0, _replayWindowSize, -1);
    _windowHead    = 0;
  }

  /// Tear down the current session.
  ///
  /// Called on disconnect, authentication failure, or E-stop lockout.
  /// All subsequent inbound packets will be rejected until a new session begins.
  void endSession() {
    _sessionId     = 0;
    _seqCounter    = 0;
    _sessionActive = false;
    _inboundWindow.fillRange(0, _replayWindowSize, -1);
    _windowHead    = 0;
  }

  /// Returns the next outbound sequence number and increments the counter.
  ///
  /// Counter wraps at 0xFFFFFFFF — in a long-lived deployment the session
  /// should be renewed before wrap-around occurs.
  int nextOutboundSeq() {
    if (_seqCounter >= 0xFFFFFFFF) {
      // Wrap — operational sessions should never reach this in practice
      // (at 100 ms heartbeat, overflow takes ~136 years).
      _seqCounter = 0;
    }
    return _seqCounter++;
  }

  /// Current UTC timestamp in milliseconds (embedded in every packet header).
  int nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Validate an inbound packet's header fields against the active session.
  ///
  /// Returns [ReplayValidationResult.valid] only when:
  ///   • a session is active
  ///   • [packetSessionId] matches the current session
  ///   • [timestampMs] is within [_maxPacketAgeMs] of the device clock
  ///   • [seqCounter] has not been seen before in the rolling window
  ReplayValidationResult validateInbound({
    required int timestampMs,
    required int seqCounter,
    required int packetSessionId,
  }) {
    if (!_sessionActive) return ReplayValidationResult.noSession;

    if (packetSessionId != _sessionId) return ReplayValidationResult.sessionMismatch;

    final delta = (nowMs() - timestampMs).abs();
    if (delta > _maxPacketAgeMs) return ReplayValidationResult.expired;

    if (_inboundWindow.contains(seqCounter)) return ReplayValidationResult.duplicate;

    // Accept — record in the rolling window.
    _inboundWindow[_windowHead] = seqCounter;
    _windowHead = (_windowHead + 1) % _replayWindowSize;
    return ReplayValidationResult.valid;
  }
}

/// Result of an inbound packet replay / session validation check.
enum ReplayValidationResult {
  /// Packet is valid and fresh — safe to process.
  valid,

  /// No active session; the PLC has not authenticated this operator.
  noSession,

  /// The packet's session_id does not match the active session.
  /// Possible replay from a previous session or a rogue sender.
  sessionMismatch,

  /// Packet timestamp is outside the acceptable freshness window.
  /// Indicates a replay attack or severe clock skew.
  expired,

  /// Sequence number was already seen — duplicate or replayed packet.
  duplicate,
}
