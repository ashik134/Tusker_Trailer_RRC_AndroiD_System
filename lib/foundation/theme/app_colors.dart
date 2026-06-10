import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dark industrial palette (Control Screen, Settings Screen, etc.)
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF0D1117);
  static const Color backgroundTop = Color(0xFF0C1A26);
  static const Color backgroundBottom = Color(0xFF061018);

  // Panels
  static const Color panel = Color(0xFF102131);
  static const Color panelAlt = Color(0xFF142838);
  static const Color panelStroke = Color(0xFF24394C);
  static const Color inputFill = Color(0xFF0B1823);

  // Brand
  static const Color accent = Color(0xFFFFB000);
  static const Color accentSoft = Color(0xFF3B2C0B);

  // Semantic
  static const Color success = Color(0xFF38C793);
  static const Color successSoft = Color(0xFF123527);
  static const Color info = Color(0xFF4BB7F3);
  static const Color disabled = Color(0xFF556270);

  // ── Direction outputs ─────────────────────────────────────────────────────
  static const Color upColor = Color(0xFF238636);
  static const Color upColorLight = Color(0xFF3FB950);
  static const Color downColor = Color(0xFF1F6FEB);
  static const Color downColorLight = Color(0xFF58A6FF);
  static const Color leftColor = Color(0xFFC07800);
  static const Color leftColorLight = Color(0xFFF2B84B);
  static const Color rightColor = Color(0xFF0F8B8D);
  static const Color rightColorLight = Color(0xFF38BFC2);
  static const Color fastColor = Color(0xFFD29922);
  static const Color fastColorLight = Color(0xFFE3B341);

  // ── Emergency Stop ────────────────────────────────────────────────────────
  static const Color eStopColor = Color(0xFFDA3633);
  static const Color eStopColorLight = Color(0xFFF85149);

  // ── Danger / error ────────────────────────────────────────────────────────
  static const Color danger = Color(0xFFE24949);
  static const Color dangerSoft = Color(0xFF3E1414);

  // ── Idle / neutral ────────────────────────────────────────────────────────
  static const Color idleColor = Color(0xFF30363D);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF3F6F9);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF94A6B7);

  // ── Border ───────────────────────────────────────────────────────────────
  static const Color border = Color(0xFF30363D);
}

// ─────────────────────────────────────────────────────────────────────────────
// Light industrial palette (Connection Screen, Login Screen, etc.)
// ─────────────────────────────────────────────────────────────────────────────

class ConnectionColors {
  ConnectionColors._();

  // Backgrounds
  static const Color background = Color(0xFFF0F3F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF8FAFC);

  // Brand
  static const Color primary = Color(0xFF1C3A5E);
  static const Color primarySoft = Color(0xFFE6EDF6);

  // Semantic: connected
  static const Color connected = Color(0xFF0D8A4A);
  static const Color connectedBg = Color.fromARGB(255, 234, 249, 249);
  static const Color connectedBorder = Color(0xFFA3DFC0);

  // Semantic: scanning / connecting
  static const Color scanning = Color(0xFF1D5FA8);
  static const Color scanningBg = Color(0xFFE8F1FB);
  static const Color scanningBorder = Color(0xFF93BDE9);

  // Semantic: warning
  static const Color warning = Color(0xFFC07800);
  static const Color warningBg = Color(0xFFFFF8E6);
  static const Color warningBorder = Color(0xFFEDC96A);

  // Semantic: error
  static const Color error = Color(0xFFCC2222);
  static const Color errorBg = Color(0xFFFDF0F0);
  static const Color errorBorder = Color(0xFFF0AAAA);

  // Neutral
  static const Color neutral = Color(0xFF68778A);
  static const Color neutralBg = Color(0xFFF1F4F8);
  static const Color neutralBorder = Color(0xFFCDD5E0);

  // Text
  static const Color textPrimary = Color(0xFF0F1B2D);
  static const Color textSecondary = Color(0xFF3A4F68);
  static const Color textMuted = Color(0xFF68778A);

  // Border / divider
  static const Color border = Color(0xFFD0D9E4);
  static const Color divider = Color(0xFFE8ECF2);
}
