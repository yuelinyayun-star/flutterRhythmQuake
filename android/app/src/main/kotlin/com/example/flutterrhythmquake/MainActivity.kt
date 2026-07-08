package com.example.flutterrhythmquake

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private companion object {
        const val TARGET_REFRESH_RATE = 60f
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyDisplayFrameRateLimit()
    }

    override fun onResume() {
        super.onResume()
        applyDisplayFrameRateLimit()
    }

    private fun applyDisplayFrameRateLimit() {
        val attrs = window.attributes
        attrs.preferredRefreshRate = TARGET_REFRESH_RATE

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val modes = window.decorView.display?.supportedModes
            val selectedMode = modes
                ?.filter { it.refreshRate <= TARGET_REFRESH_RATE + 0.5f }
                ?.maxByOrNull { it.refreshRate }
                ?: modes?.minByOrNull { abs(it.refreshRate - TARGET_REFRESH_RATE) }
            if (selectedMode != null) {
                attrs.preferredDisplayModeId = selectedMode.modeId
            }
        }

        window.attributes = attrs
    }
}
