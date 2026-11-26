package com.example.flutterrhythmquake

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.hardware.display.DisplayManager
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

internal class ExternalSubtitleWindow(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val eewBodyTop = 160
    private val app = activity.applicationContext
    private val channel = MethodChannel(messenger, "flutterrhythmquake/external_subtitle")
    private val windowContext by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val display = app.getSystemService(DisplayManager::class.java)
                .getDisplay(Display.DEFAULT_DISPLAY)
            app.createDisplayContext(display)
                .createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
        } else {
            app
        }
    }
    private val windowManager by lazy { windowContext.getSystemService(WindowManager::class.java) }
    private var root: FrameLayout? = null

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestPermission" -> {
                        if (!Settings.canDrawOverlays(app)) {
                            activity.startActivity(Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:${app.packageName}"),
                            ))
                        }
                    }
                    "present" -> present(call.arguments as List<*>)
                    "close" -> hide()
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                result.success(null)
            } catch (error: RuntimeException) {
                result.error("external_subtitle_window", error.message, null)
            }
        }
    }

    private fun dp(value: Int) =
        (value * windowContext.resources.displayMetrics.density).roundToInt()

    private fun present(lines: List<*>) {
        if (lines.isEmpty() || !Settings.canDrawOverlays(app)) {
            hide()
            return
        }
        val metrics = windowContext.resources.displayMetrics
        val width = minOf(dp(660), metrics.widthPixels - dp(24)).coerceAtLeast(dp(80))
        val content = root ?: FrameLayout(windowContext)
        content.removeAllViews()
        val eewContent = LinearLayout(windowContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        }
        val infoContent = LinearLayout(windowContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP or Gravity.LEFT
        }
        content.addView(
            eewContent,
            FrameLayout.LayoutParams(
                width,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL,
            ),
        )
        content.addView(
            infoContent,
            FrameLayout.LayoutParams(
                width,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.LEFT,
            ).apply {
                leftMargin = dp(12)
            },
        )
        for (item in lines) {
            val row = item as? Map<*, *> ?: continue
            val style = row["style"] as? String ?: continue
            if (style == "belowEew") {
                continue
            }
            val info = style == "infoTitle" || style == "info" || style == "infoDetail"
            val target = if (info) infoContent else eewContent
            if (style == "gap") {
                target.addView(View(windowContext), LinearLayout.LayoutParams(width, dp(6)))
                continue
            }
            val value = row["text"] as? String ?: continue
            if (value.isEmpty()) continue
            val title = style == "eewTitle"
            val badge = row["badge"] as? String ?: ""
            val japanese = row["japanese"] == true
            val jmaIntensity = japanese && badge.isNotEmpty()
            val jmaTextBlock = japanese && !title
            val leftAligned = when (style) {
                "info", "infoDetail" -> true
                "eewBody", "jmaAreas", "eewDetail", "infoTitle" -> japanese
                else -> false
            }
            val lineWidth = if (jmaTextBlock) minOf(width, dp(418)) else width
            val caption = TextView(windowContext).apply {
                text = if (badge.isEmpty() || jmaIntensity) value else "$badge　$value"
                setTextColor(Color.WHITE)
                textSize = when (style) {
                    "eewTitle" -> 22f
                    "eewBody", "info" -> 18f
                    else -> 16f
                }
                typeface = Typeface.DEFAULT_BOLD
                gravity = if (leftAligned) Gravity.TOP or Gravity.LEFT else Gravity.CENTER
                setPadding(if (jmaIntensity) dp(8) else dp(12), dp(2), dp(12), dp(3))
                if (title) {
                    setBackgroundColor(Color.rgb(219, 16, 23))
                } else {
                    setShadowLayer(dp(3).toFloat(), 0f, 0f, Color.BLACK)
                }
            }
            val line = if (jmaIntensity) {
                val label = TextView(windowContext).apply {
                    text = badge
                    setSingleLine(true)
                    gravity = Gravity.CENTER
                    setTextColor(Color.WHITE)
                    setBackgroundColor(Color.rgb(8, 134, 45))
                    setTextSize(TypedValue.COMPLEX_UNIT_PX, caption.textSize)
                    typeface = Typeface.DEFAULT_BOLD
                    setPadding(dp(8), dp(2), dp(8), dp(3))
                }
                LinearLayout(windowContext).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.TOP or Gravity.LEFT
                    layoutDirection = View.LAYOUT_DIRECTION_LTR
                    setPadding(dp(12), 0, 0, 0)
                    addView(label, LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ))
                    addView(caption, LinearLayout.LayoutParams(
                        0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
                    ))
                }
            } else {
                caption
            }
            line.visibility = if (row["hidden"] == true) View.INVISIBLE else View.VISIBLE
            val widthMode = if (leftAligned) View.MeasureSpec.EXACTLY else View.MeasureSpec.AT_MOST
            val spec = View.MeasureSpec.makeMeasureSpec(lineWidth, widthMode)
            line.measure(spec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            target.addView(line, LinearLayout.LayoutParams(
                if (leftAligned) lineWidth else LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
            if (style == "eewTitle") {
                val titleGap = (dp(eewBodyTop) - line.measuredHeight).coerceAtLeast(0)
                target.addView(View(windowContext), LinearLayout.LayoutParams(width, titleGap))
            }
        }
        if (root != null) return

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(16)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                alpha = app.getSystemService(InputManager::class.java)
                    .maximumObscuringOpacityForTouch
            }
            title = "RhythmQuake earthquake subtitles"
        }
        windowManager.addView(content, params)
        root = content
    }

    private fun hide() {
        val content = root ?: return
        root = null
        windowManager.removeViewImmediate(content)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        hide()
    }

}
