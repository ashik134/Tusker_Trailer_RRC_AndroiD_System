package com.example.tusker_trailer_rrc

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Fade out the platform splash at handoff time for a calm transition.
            splashScreen.setOnExitAnimationListener { splashScreenView ->
                splashScreenView
                    .animate()
                    .alpha(0f)
                    .setDuration(220L)
                    .withEndAction { splashScreenView.remove() }
                    .start()
            }
        }

        super.onCreate(savedInstanceState)
    }
}
