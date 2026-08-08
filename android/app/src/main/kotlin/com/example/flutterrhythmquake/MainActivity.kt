package com.example.flutterrhythmquake

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private companion object {
        const val TARGET_REFRESH_RATE = 60f
        const val SYSTEM_SETTINGS_CHANNEL = "flutterrhythmquake/system_settings"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "openNotificationSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                } else {
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    )
                }
                startActivity(intent)
                result.success(true)
            } catch (error: Exception) {
                result.error("OPEN_NOTIFICATION_SETTINGS_FAILED", error.message, null)
            }
        }
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
