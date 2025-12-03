package com.example.coaching_institute_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin

class MainActivity: FlutterActivity() {
    // ✅ This is the fix: Enable Hybrid Composition Texture Mode
    override fun getRenderMode() = RenderMode.texture
    override fun getTransparencyMode() = TransparencyMode.transparent

    private val CHANNEL = "focus_mode_overlay_channel"
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var isOverlayVisible = false

    @SuppressLint("ClickableViewAccessibility")
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        // Register auto plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Register WebView plugin (if required in your setup)
        flutterEngine.plugins.add(WebViewFlutterPlugin())

        super.configureFlutterEngine(flutterEngine)

        // Set up method channel for overlay functionality
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showOverlay" -> {
                    val message = call.argument<String>("message")
                    showOverlay(message)
                    result.success(true)
                }
                "hideOverlay" -> {
                    hideOverlay()
                    result.success(true)
                }
                "checkOverlayPermission" -> {
                    result.success(checkOverlayPermission())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true // For older Android versions, permission is granted by default
        }
    }

    @SuppressLint("InflateParams", "ClickableViewAccessibility")
    private fun showOverlay(message: String?) {
        runOnUiThread {
            if (isOverlayVisible) return@runOnUiThread
            
            // Check permission
            if (!checkOverlayPermission()) {
                // Permission not granted, notify Flutter
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onPermissionRequired", null)
                return@runOnUiThread
            }
            
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            
            // Create overlay view
            val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
            overlayView = inflater.inflate(R.layout.overlay_layout, null)
            
            // Set message
            val messageText = overlayView!!.findViewById<TextView>(R.id.overlay_message)
            messageText.text = message ?: "You are in focus mode, focus on studies"
            
            // Set return button click listener
            val returnButton = overlayView!!.findViewById<Button>(R.id.return_button)
            returnButton.setOnClickListener {
                // Hide overlay
                hideOverlay()
                
                // Notify Flutter to return to app
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onReturnToStudy", null)
                
                // Bring app to foreground
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launchIntent)
            }
            
            // Make overlay non-interactive except for the return button
            overlayView!!.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        // Check if touch is on the button
                        val button = overlayView!!.findViewById<Button>(R.id.return_button)
                        val buttonRect = android.graphics.Rect()
                        button.getGlobalVisibleRect(buttonRect)
                        
                        if (buttonRect.contains(event.rawX.toInt(), event.rawY.toInt())) {
                            // Allow button click
                            return@setOnTouchListener false
                        }
                        // Block all other touches
                        return@setOnTouchListener true
                    }
                }
                false
            }
            
            // Set layout parameters
            val params = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                    PixelFormat.TRANSLUCENT
                )
            } else {
                WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                    PixelFormat.TRANSLUCENT
                )
            }
            
            params.gravity = Gravity.TOP or Gravity.START
            params.x = 0
            params.y = 0
            
            // Add overlay view
            try {
                windowManager!!.addView(overlayView, params)
                isOverlayVisible = true
                
                // Notify Flutter
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onOverlayShown", null)
                
                // Log success
                android.util.Log.d("MainActivity", "✅ Overlay shown successfully")
            } catch (e: Exception) {
                e.printStackTrace()
                // Notify Flutter of error
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onOverlayError", e.message)
            }
        }
    }
    
    private fun hideOverlay() {
        runOnUiThread {
            if (!isOverlayVisible || overlayView == null) return@runOnUiThread
            
            try {
                windowManager?.removeView(overlayView)
                overlayView = null
                isOverlayVisible = false
                
                // Notify Flutter
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onOverlayHidden", null)
                
                // Log success
                android.util.Log.d("MainActivity", "✅ Overlay hidden successfully")
            } catch (e: Exception) {
                e.printStackTrace()
                // Notify Flutter of error
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onOverlayError", e.message)
            }
        }
    }
    
    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }
    
    override fun onResume() {
        super.onResume()
        // Hide overlay when app comes to foreground
        hideOverlay()
    }
    
    override fun onPause() {
        super.onPause()
        // Note: We'll show overlay from Flutter side when app goes to background
        // during focus mode
    }
}