package com.example.coaching_institute_app

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin
import org.json.JSONArray
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    // ✅ Enable Hybrid Composition Texture Mode
    override fun getRenderMode() = RenderMode.texture
    override fun getTransparencyMode() = TransparencyMode.transparent

    private val CHANNEL = "focus_mode_overlay_channel"
    private val TAG = "FocusOverlay"
    
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var isOverlayVisible = false
    private var sharedPreferences: SharedPreferences? = null
    private val handler = Handler(Looper.getMainLooper())
    
    // 🆕 Track force hide state
    private var isForceHiding = false
    private var isAppsListExpanded = false
    
    // 🆕 Store allowed apps data
    private var allowedAppsData: String = "[]"

    @SuppressLint("ClickableViewAccessibility")
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        // Register auto plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Register WebView plugin (if required in your setup)
        flutterEngine.plugins.add(WebViewFlutterPlugin())

        super.configureFlutterEngine(flutterEngine)
        
        // Initialize SharedPreferences
        sharedPreferences = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        // Load allowed apps from SharedPreferences
        allowedAppsData = sharedPreferences?.getString("overlay_allowed_apps", "[]") ?: "[]"

        // Set up method channel for overlay functionality
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showOverlay" -> {
                    val message = call.argument<String>("message")
                    val success = showOverlay(message)
                    result.success(success)
                }
                "hideOverlay" -> {
                    val success = hideOverlay()
                    result.success(success)
                }
                "forceHideOverlay" -> {
                    // 🆕 NEW: Force hide with aggressive cleanup
                    val success = forceHideOverlay()
                    result.success(success)
                }
                "checkOverlayPermission" -> {
                    result.success(checkOverlayPermission())
                }
                "isOverlayShowing" -> {
                    // 🆕 NEW: Check if overlay is currently showing
                    result.success(isOverlayVisible)
                }
                // 🆕 NEW: Methods for allowed apps management
                "updateAllowedApps" -> {
                    val appsJson = call.argument<String>("apps") ?: "[]"
                    val success = updateAllowedApps(appsJson)
                    result.success(success)
                }
                "getAllowedApps" -> {
                    val apps = getAllowedApps()
                    result.success(apps)
                }
                "clearAllowedApps" -> {
                    val success = clearAllowedApps()
                    result.success(success)
                }
                "refreshAllowedAppsInOverlay" -> {
                    // 🆕 NEW: Refresh allowed apps in the overlay
                    val success = refreshAllowedAppsInOverlay()
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        Log.d(TAG, "✅ MainActivity configured with method channel")
    }

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true // For older Android versions, permission is granted by default
        }
    }
    
    // ========== NEW HELPER METHOD: Check for System Dialog ==========
    /**
     * Checks if there's a system dialog (like file picker) currently active in our app.
     * This prevents the overlay from showing when user is selecting files within the app.
     */
    private fun hasSystemAlertDialog(context: Context): Boolean {
        try {
            // Get the window manager service
            val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            
            // Check all windows
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                @Suppress("DEPRECATION")
                val display = windowManager.defaultDisplay
                
                // For API level 30+, we need to check window types differently
                // But the key insight is that system dialogs have specific window types
                // We'll use a simpler approach that works for file pickers
                
                // Alternative approach: Check if there are any Dialog-themed activities
                val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                
                // Get the currently focused window/activity information
                @Suppress("DEPRECATION")
                val runningTasks = activityManager.getRunningTasks(1)
                if (runningTasks.isNotEmpty()) {
                    val topActivity = runningTasks[0].topActivity
                    if (topActivity != null && topActivity.packageName == packageName) {
                        // Check if it's a dialog activity
                        val className = topActivity.className?.lowercase() ?: ""
                        
                        // Common dialog/picker class name patterns
                        val dialogPatterns = listOf(
                            "dialog",
                            "picker",
                            "chooser",
                            "file",
                            "document",
                            "photo",
                            "image",
                            "camera",
                            "media",
                            "gallery",
                            "selector"
                        )
                        
                        // Check if the activity name contains any dialog pattern
                        for (pattern in dialogPatterns) {
                            if (className.contains(pattern)) {
                                Log.d(TAG, "🔍 Detected system dialog activity: $className")
                                return true
                            }
                        }
                    }
                }
                
                // Additional check: Look for specific window types that indicate dialogs
                // This is a more direct approach for detecting overlays
                try {
                    // Use reflection to access WindowManager's views (advanced approach)
                    // This checks if there are any TYPE_APPLICATION windows that aren't our main activity
                    val windowManagerImpl = windowManager.javaClass
                    val viewsField = windowManagerImpl.getDeclaredField("mViews")
                    viewsField.isAccessible = true
                    val views = viewsField.get(windowManager) as? Array<View>
                    
                    if (views != null) {
                        for (view in views) {
                            val params = view.layoutParams as? WindowManager.LayoutParams
                            if (params != null) {
                                // Check for dialog-type windows
                                val windowType = params.type
                                val isDialogType = windowType == WindowManager.LayoutParams.TYPE_APPLICATION_PANEL ||
                                                  windowType == WindowManager.LayoutParams.TYPE_APPLICATION_ATTACHED_DIALOG ||
                                                  windowType == WindowManager.LayoutParams.TYPE_APPLICATION_SUB_PANEL ||
                                                  windowType == WindowManager.LayoutParams.TYPE_APPLICATION_MEDIA
                                
                                if (isDialogType) {
                                    Log.d(TAG, "🔍 Detected dialog window type: $windowType")
                                    return true
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not check window views: ${e.message}")
                    // Fall through to other methods
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking for system dialog: ${e.message}")
        }
        
        return false
    }

    // ========== UPDATED METHOD: Show Overlay with Dialog Check ==========
private fun showOverlay(message: String?): Boolean {
    // 🔥 NEW APPROACH: Track activity state to detect dialogs
    // When file picker opens, our activity goes through onPause() but quickly comes back
    
    val currentTime = System.currentTimeMillis()
    val lastPauseTime = sharedPreferences?.getLong("last_pause_time", 0) ?: 0
    val timeSincePause = currentTime - lastPauseTime
    
    Log.d(TAG, "⏰ Time since activity pause: ${timeSincePause}ms")
    
    // CRITICAL FIX: If activity was paused very recently (< 800ms), it's a dialog
    if (timeSincePause < 800) {
        Log.d(TAG, "🚫 Recent activity pause detected - likely dialog opening, NOT showing overlay")
        
        // Add extra delay to be sure
        handler.postDelayed({
            if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
                // Check current window state after delay
                val windowNow = window
                val decorViewNow = windowNow?.decorView
                val hasFocusNow = decorViewNow != null && decorViewNow.hasWindowFocus()
                
                // If window STILL doesn't have focus after delay, then show overlay
                if (!hasFocusNow) {
                    Log.d(TAG, "🔄 Dialog closed or user left app, showing overlay")
                    showOverlayAfterDelay(message)
                } else {
                    Log.d(TAG, "🔄 Window regained focus - still in dialog")
                }
            }
        }, 1000) // 1 second delay
        
        return false
    }
    
    // 🆕 CRITICAL: Check if user is logged in and focus mode is active
    if (!isUserLoggedIn()) {
        Log.w(TAG, "⚠️ Cannot show overlay: User not logged in")
        return false
    }
    
    if (!isFocusModeActive()) {
        Log.w(TAG, "⚠️ Cannot show overlay: Focus mode not active")
        return false
    }
    
    // 🔥 DIRECT SHOW OVERLAY (no delay needed)
    runOnUiThread {
        if (isOverlayVisible) {
            Log.d(TAG, "⚠️ Overlay already visible, skipping")
            return@runOnUiThread
        }
        
        if (isForceHiding) {
            Log.d(TAG, "⚠️ Force hiding in progress, cannot show overlay")
            return@runOnUiThread
        }
        
        // Check permission
        if (!checkOverlayPermission()) {
            Log.w(TAG, "❌ Overlay permission not granted")
            // Permission not granted, notify Flutter
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("onPermissionRequired", null)
            }
            return@runOnUiThread
        }
        
        try {
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
                Log.d(TAG, "🔙 Return button clicked")
                
                // Hide overlay
                hideOverlay()
                
                // Notify Flutter to return to app
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, CHANNEL).invokeMethod("onReturnToStudy", null)
                }
                
                // Bring app to foreground
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launchIntent)
            }
            
            // Set allowed apps dropdown header click listener
            val allowedAppsHeader = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_header)
            val dropdownArrow = overlayView!!.findViewById<ImageView>(R.id.dropdown_arrow)
            val allowedAppsListContainer = overlayView!!.findViewById<ScrollView>(R.id.allowed_apps_list_container)
            val instructionsText = overlayView!!.findViewById<TextView>(R.id.instructions_text)
            
            allowedAppsHeader.setOnClickListener {
                isAppsListExpanded = !isAppsListExpanded
                
                if (isAppsListExpanded) {
                    // Expand the apps list
                    allowedAppsListContainer.visibility = View.VISIBLE
                    instructionsText.visibility = View.GONE
                    dropdownArrow.setImageResource(android.R.drawable.arrow_up_float)
                    
                    // Load and display allowed apps
                    loadAllowedAppsIntoOverlay()
                    Log.d(TAG, "📱 Expanded allowed apps list")
                } else {
                    // Collapse the apps list
                    allowedAppsListContainer.visibility = View.GONE
                    instructionsText.visibility = View.VISIBLE
                    dropdownArrow.setImageResource(android.R.drawable.arrow_down_float)
                    Log.d(TAG, "📱 Collapsed allowed apps list")
                }
            }
            
            // Initially load allowed apps (collapsed state)
            loadAllowedAppsIntoOverlay()
            
            // Make overlay non-interactive except for the buttons and allowed apps header
            overlayView!!.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        // Check if touch is on any interactive element
                        val returnButton = overlayView!!.findViewById<Button>(R.id.return_button)
                        val allowedAppsHeader = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_header)
                        val allowedAppsList = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_list)
                        
                        val returnRect = android.graphics.Rect()
                        val headerRect = android.graphics.Rect()
                        val listRect = android.graphics.Rect()
                        
                        returnButton.getGlobalVisibleRect(returnRect)
                        allowedAppsHeader.getGlobalVisibleRect(headerRect)
                        
                        // Check all app items in the list
                        var isTouchOnAppItem = false
                        if (allowedAppsListContainer.visibility == View.VISIBLE) {
                            for (i in 0 until allowedAppsList.childCount) {
                                val child = allowedAppsList.getChildAt(i)
                                child.getGlobalVisibleRect(listRect)
                                if (listRect.contains(event.rawX.toInt(), event.rawY.toInt())) {
                                    isTouchOnAppItem = true
                                    break
                                }
                            }
                        }
                        
                        if (returnRect.contains(event.rawX.toInt(), event.rawY.toInt()) ||
                            headerRect.contains(event.rawX.toInt(), event.rawY.toInt()) ||
                            isTouchOnAppItem) {
                            // Allow click on interactive elements
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
            windowManager!!.addView(overlayView, params)
            isOverlayVisible = true
            
            // Update SharedPreferences
            sharedPreferences?.edit()?.apply {
                putBoolean("flutter.overlay_visible", true)
                apply()
            }
            
            // Notify Flutter
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("onOverlayShown", null)
            }
            
            Log.d(TAG, "✅ Overlay shown successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing overlay: ${e.message}", e)
            
            // Clean up on error
            overlayView = null
            windowManager = null
            isOverlayVisible = false
            
            // Notify Flutter of error
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("onOverlayError", e.message)
            }
        }
    }
    
    return isOverlayVisible
}
    
 private fun showOverlayAfterDelay(message: String?) {
    runOnUiThread {
        if (isOverlayVisible || isForceHiding) {
            return@runOnUiThread
        }
        
        // Check permission
        if (!checkOverlayPermission()) {
            Log.w(TAG, "❌ Overlay permission not granted")
            return@runOnUiThread
        }
        
        try {
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
                Log.d(TAG, "🔙 Return button clicked")
                
                // Hide overlay
                hideOverlay()
                
                // Notify Flutter to return to app
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, CHANNEL).invokeMethod("onReturnToStudy", null)
                }
                
                // Bring app to foreground
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launchIntent)
            }
            
            // Set allowed apps dropdown header click listener
            val allowedAppsHeader = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_header)
            val dropdownArrow = overlayView!!.findViewById<ImageView>(R.id.dropdown_arrow)
            val allowedAppsListContainer = overlayView!!.findViewById<ScrollView>(R.id.allowed_apps_list_container)
            val instructionsText = overlayView!!.findViewById<TextView>(R.id.instructions_text)
            
            allowedAppsHeader.setOnClickListener {
                isAppsListExpanded = !isAppsListExpanded
                
                if (isAppsListExpanded) {
                    // Expand the apps list
                    allowedAppsListContainer.visibility = View.VISIBLE
                    instructionsText.visibility = View.GONE
                    dropdownArrow.setImageResource(android.R.drawable.arrow_up_float)
                    
                    // Load and display allowed apps
                    loadAllowedAppsIntoOverlay()
                    Log.d(TAG, "📱 Expanded allowed apps list")
                } else {
                    // Collapse the apps list
                    allowedAppsListContainer.visibility = View.GONE
                    instructionsText.visibility = View.VISIBLE
                    dropdownArrow.setImageResource(android.R.drawable.arrow_down_float)
                    Log.d(TAG, "📱 Collapsed allowed apps list")
                }
            }
            
            // Initially load allowed apps (collapsed state)
            loadAllowedAppsIntoOverlay()
            
            // Make overlay non-interactive except for the buttons and allowed apps header
            overlayView!!.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        // Check if touch is on any interactive element
                        val returnButton = overlayView!!.findViewById<Button>(R.id.return_button)
                        val allowedAppsHeader = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_header)
                        val allowedAppsList = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_list)
                        
                        val returnRect = android.graphics.Rect()
                        val headerRect = android.graphics.Rect()
                        val listRect = android.graphics.Rect()
                        
                        returnButton.getGlobalVisibleRect(returnRect)
                        allowedAppsHeader.getGlobalVisibleRect(headerRect)
                        
                        // Check all app items in the list
                        var isTouchOnAppItem = false
                        if (allowedAppsListContainer.visibility == View.VISIBLE) {
                            for (i in 0 until allowedAppsList.childCount) {
                                val child = allowedAppsList.getChildAt(i)
                                child.getGlobalVisibleRect(listRect)
                                if (listRect.contains(event.rawX.toInt(), event.rawY.toInt())) {
                                    isTouchOnAppItem = true
                                    break
                                }
                            }
                        }
                        
                        if (returnRect.contains(event.rawX.toInt(), event.rawY.toInt()) ||
                            headerRect.contains(event.rawX.toInt(), event.rawY.toInt()) ||
                            isTouchOnAppItem) {
                            // Allow click on interactive elements
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
            windowManager!!.addView(overlayView, params)
            isOverlayVisible = true
            
            // Update SharedPreferences
            sharedPreferences?.edit()?.apply {
                putBoolean("flutter.overlay_visible", true)
                apply()
            }
            
            // Notify Flutter
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("onOverlayShown", null)
            }
            
            Log.d(TAG, "✅ Overlay shown successfully (delayed)")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing delayed overlay: ${e.message}", e)
            
            // Clean up on error
            overlayView = null
            windowManager = null
            isOverlayVisible = false
            
            // Notify Flutter of error
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("onOverlayError", e.message)
            }
        }
    }
}
    
    // 🆕 Check if user is logged in
    private fun isUserLoggedIn(): Boolean {
        val accessToken = sharedPreferences?.getString("flutter.accessToken", null)
        val username = sharedPreferences?.getString("flutter.username", null)
        val isLoggedIn = !accessToken.isNullOrEmpty() && !username.isNullOrEmpty()
        
        Log.d(TAG, "🔐 User logged in check: $isLoggedIn (token: ${!accessToken.isNullOrEmpty()}, user: ${!username.isNullOrEmpty()})")
        return isLoggedIn
    }
    
    // 🆕 Check if focus mode is active
    private fun isFocusModeActive(): Boolean {
        val isFocusMode = sharedPreferences?.getBoolean("flutter.is_focus_mode", false) ?: false
        Log.d(TAG, "🎯 Focus mode active check: $isFocusMode")
        return isFocusMode
    }
    
    // 🆕 Load allowed apps into the overlay list
    private fun loadAllowedAppsIntoOverlay() {
        try {
            val allowedAppsList = overlayView?.findViewById<LinearLayout>(R.id.allowed_apps_list)
            if (allowedAppsList == null) {
                Log.w(TAG, "⚠️ Allowed apps list view not found")
                return
            }
            
            // Clear existing views
            allowedAppsList.removeAllViews()
            
            // Get allowed apps from storage
            val allowedAppsJson = getAllowedApps()
            val allowedApps = JSONArray(allowedAppsJson)
            
            if (allowedApps.length() == 0) {
                // Show empty state message
                val emptyTextView = TextView(this).apply {
                    text = "No allowed apps yet\n\nGo to 'Allowed Apps' tab in the app to add apps"
                    textSize = 14f
                    setTextColor(android.graphics.Color.GRAY)
                    gravity = android.view.Gravity.CENTER
                    setPadding(0, 40, 0, 40)
                    textAlignment = View.TEXT_ALIGNMENT_CENTER
                }
                allowedAppsList.addView(emptyTextView)
                Log.d(TAG, "📱 Showing empty state for allowed apps")
                return
            }
            
            // Add each allowed app as a clickable item
            for (i in 0 until allowedApps.length()) {
                try {
                    val app = allowedApps.getJSONObject(i)
                    val appName = app.getString("appName")
                    val packageName = app.getString("packageName")
                    val iconBytes = app.optString("iconBytes", "")
                    
                    Log.d(TAG, "📱 Adding app to overlay list: $appName ($packageName)")
                    
                    // Inflate app item layout
                    val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
                    val appItemView = inflater.inflate(R.layout.app_item_overlay_layout, null)
                    
                    // Set app icon
                    val appIcon = appItemView.findViewById<ImageView>(R.id.app_icon)
                    if (iconBytes.isNotEmpty() && iconBytes != "null") {
                        try {
                            val iconBytesArray = Base64.decode(iconBytes, Base64.DEFAULT)
                            val bitmap = BitmapFactory.decodeByteArray(iconBytesArray, 0, iconBytesArray.size)
                            if (bitmap != null) {
                                appIcon.setImageBitmap(bitmap)
                                Log.d(TAG, "   ✅ Loaded icon for $appName")
                            } else {
                                appIcon.setImageResource(R.mipmap.ic_launcher)
                                Log.d(TAG, "   ⚠️ Could not decode icon for $appName")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error decoding icon for $appName: ${e.message}")
                            appIcon.setImageResource(R.mipmap.ic_launcher)
                        }
                    } else {
                        appIcon.setImageResource(R.mipmap.ic_launcher)
                        Log.d(TAG, "   ⚠️ No icon for $appName")
                    }
                    
                    // Set app name
                    val appNameView = appItemView.findViewById<TextView>(R.id.app_name)
                    appNameView.text = appName
                    
                    // Set package name
                    val packageNameView = appItemView.findViewById<TextView>(R.id.package_name)
                    packageNameView.text = packageName
                    
                    // Set click listener to open the app
                    appItemView.setOnClickListener {
                        Log.d(TAG, "📱 App clicked in overlay: $appName ($packageName)")
                        try {
                            // First, hide the overlay temporarily
                            hideOverlay()
                            
                            // Try to launch the app
                            val intent = packageManager.getLaunchIntentForPackage(packageName)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                
                                // Notify Flutter that app was launched (for tracking)
                                val appData = JSONObject().apply {
                                    put("appName", appName)
                                    put("packageName", packageName)
                                }
                                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                                    MethodChannel(it, CHANNEL).invokeMethod("onAppLaunch", appData.toString())
                                }
                                
                                Log.d(TAG, "✅ App launched: $appName")
                                
                                // IMPORTANT: Don't show overlay again immediately
                                // The overlay will be shown again when user leaves the allowed app
                            } else {
                                Log.e(TAG, "❌ Could not find launch intent for: $packageName")
                                // Show overlay again if app couldn't be opened
                                showOverlay("Could not open $appName")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error launching app: ${e.message}", e)
                            // Show overlay again on error
                            showOverlay("Error opening $appName")
                        }
                    }
                    
                    allowedAppsList.addView(appItemView)
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error processing app item: ${e.message}")
                }
            }
            
            Log.d(TAG, "✅ Loaded ${allowedApps.length()} apps into overlay list")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error loading allowed apps into overlay: ${e.message}", e)
        }
    }
    
    // 🆕 Refresh allowed apps in overlay
    private fun refreshAllowedAppsInOverlay(): Boolean {
        Log.d(TAG, "🔄 Refreshing allowed apps in overlay")
        
        return try {
            runOnUiThread {
                if (isOverlayVisible && isAppsListExpanded) {
                    loadAllowedAppsIntoOverlay()
                }
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error refreshing allowed apps in overlay: ${e.message}", e)
            false
        }
    }
    
    // 🆕 NEW: Update allowed apps
    private fun updateAllowedApps(appsJson: String): Boolean {
        return try {
            Log.d(TAG, "📱 Updating allowed apps: ${appsJson.length} characters")
            
            // Validate JSON
            val jsonArray = JSONArray(appsJson)
            Log.d(TAG, "📱 Parsed ${jsonArray.length()} allowed apps")
            
            // Save to class variable
            allowedAppsData = appsJson
            
            // Save to SharedPreferences
            sharedPreferences?.edit()?.apply {
                putString("overlay_allowed_apps", appsJson)
                apply()
            }
            
            Log.d(TAG, "✅ Allowed apps updated successfully")
            
            // Refresh overlay if it's visible and expanded
            if (isOverlayVisible && isAppsListExpanded) {
                runOnUiThread {
                    loadAllowedAppsIntoOverlay()
                }
            }
            
            // Log first few apps for debugging
            for (i in 0 until minOf(jsonArray.length(), 3)) {
                try {
                    val app = jsonArray.getJSONObject(i)
                    val appName = app.getString("appName")
                    val packageName = app.getString("packageName")
                    val hasIcon = app.has("iconBytes") && !app.isNull("iconBytes")
                    Log.d(TAG, "   • $appName ($packageName) - Has icon: $hasIcon")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Error logging app $i: ${e.message}")
                }
            }
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating allowed apps: ${e.message}", e)
            false
        }
    }
    
    // 🆕 NEW: Get allowed apps
    private fun getAllowedApps(): String {
        Log.d(TAG, "📱 Getting allowed apps from storage")
        
        return try {
            // Load from SharedPreferences if not already loaded
            if (allowedAppsData == "[]") {
                allowedAppsData = sharedPreferences?.getString("overlay_allowed_apps", "[]") ?: "[]"
            }
            
            val jsonArray = JSONArray(allowedAppsData)
            Log.d(TAG, "📱 Returning ${jsonArray.length()} allowed apps")
            
            allowedAppsData
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting allowed apps: ${e.message}", e)
            "[]"
        }
    }
    
    // 🆕 NEW: Clear allowed apps
    private fun clearAllowedApps(): Boolean {
        Log.d(TAG, "🗑️ Clearing allowed apps")
        
        return try {
            allowedAppsData = "[]"
            
            // Clear from SharedPreferences
            sharedPreferences?.edit()?.apply {
                remove("overlay_allowed_apps")
                apply()
            }
            
            Log.d(TAG, "✅ Allowed apps cleared successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error clearing allowed apps: ${e.message}", e)
            false
        }
    }
    
    private fun hideOverlay(): Boolean {
        Log.d(TAG, "🎯 Attempting to hide overlay...")
        
        var success = false
        
        runOnUiThread {
            if (!isOverlayVisible && overlayView == null) {
                Log.d(TAG, "⚠️ Overlay already hidden")
                success = true
                return@runOnUiThread
            }
            
            try {
                // Reset apps list state
                isAppsListExpanded = false
                
                // Remove view from window manager
                overlayView?.let { view ->
                    windowManager?.let { wm ->
                        try {
                            wm.removeView(view)
                            Log.d(TAG, "✅ View removed from WindowManager")
                        } catch (e: IllegalArgumentException) {
                            Log.w(TAG, "⚠️ View not attached to WindowManager: ${e.message}")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error removing view: ${e.message}", e)
                        }
                    }
                }
                
                // Nullify references
                overlayView = null
                windowManager = null
                isOverlayVisible = false
                
                // Update SharedPreferences
                sharedPreferences?.edit()?.apply {
                    putBoolean("flutter.overlay_visible", false)
                    apply()
                }
                
                // Notify Flutter
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, CHANNEL).invokeMethod("onOverlayHidden", null)
                }
                
                Log.d(TAG, "✅ Overlay hidden successfully")
                success = true
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error hiding overlay: ${e.message}", e)
                
                // Force clean up even on error
                overlayView = null
                windowManager = null
                isOverlayVisible = false
                isAppsListExpanded = false
                
                // Notify Flutter of error
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, CHANNEL).invokeMethod("onOverlayError", e.message)
                }
            }
        }
        
        return success
    }
    
    // 🆕 NEW: Force hide overlay with aggressive cleanup
    private fun forceHideOverlay(): Boolean {
        Log.d(TAG, "🔴 FORCE HIDING OVERLAY - AGGRESSIVE MODE")
        
        isForceHiding = true
        var success = false
        
        try {
            // Attempt 1: Regular hide
            hideOverlay()
            Thread.sleep(100)
            
            // Attempt 2: Direct removal
            runOnUiThread {
                try {
                    overlayView?.let { view ->
                        // Try to remove from parent if it has one
                        (view.parent as? ViewGroup)?.removeView(view)
                        
                        // Try to remove from window manager again
                        windowManager?.removeView(view)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Force removal attempt: ${e.message}")
                }
                
                // Force nullify everything
                overlayView = null
                windowManager = null
                isOverlayVisible = false
                isAppsListExpanded = false
                
                // Clear all SharedPreferences flags
                sharedPreferences?.edit()?.apply {
                    putBoolean("flutter.overlay_visible", false)
                    putBoolean("flutter.is_focus_mode", false)
                    remove("flutter.focus_mode_start_time")
                    remove("flutter.focus_time_today")
                    apply()
                }
                
                Log.d(TAG, "✅ Force hide complete - all references cleared")
                success = true
            }
            
            // Attempt 3: Delayed final check
            handler.postDelayed({
                runOnUiThread {
                    if (overlayView != null || isOverlayVisible) {
                        Log.w(TAG, "⚠️ Overlay still exists after force hide, final cleanup...")
                        overlayView = null
                        windowManager = null
                        isOverlayVisible = false
                        isAppsListExpanded = false
                    }
                    isForceHiding = false
                }
            }, 500)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in force hide: ${e.message}", e)
            
            // Ultimate cleanup
            overlayView = null
            windowManager = null
            isOverlayVisible = false
            isAppsListExpanded = false
            isForceHiding = false
        }
        
        return success
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "📱 MainActivity onCreate")
    }
    
    override fun onResume() {
    super.onResume()
    Log.d(TAG, "📱 MainActivity onResume")
    
    // 🔥 NEW: Track when app is resumed
    sharedPreferences?.edit()?.apply {
        putLong("last_app_resume", System.currentTimeMillis())
        apply()
    }
    
    // 🆕 CRITICAL: Check if user is logged out
    if (!isUserLoggedIn()) {
        Log.d(TAG, "🚪 User logged out, force hiding overlay")
        forceHideOverlay()
        return
    }
    
    // Hide overlay when app comes to foreground (if not in focus mode)
    if (!isFocusModeActive()) {
        Log.d(TAG, "📱 App resumed without focus mode, hiding overlay")
        hideOverlay()
    }
}
    
   override fun onPause() {
    super.onPause()
    Log.d(TAG, "📱 MainActivity onPause")
    
    // 🔥 TRACK WHEN ACTIVITY PAUSES
    val pauseTime = System.currentTimeMillis()
    sharedPreferences?.edit()?.apply {
        putLong("last_pause_time", pauseTime)
        apply()
    }
    
    // 🆕 Check if user is logged out before showing overlay
    if (!isUserLoggedIn()) {
        Log.d(TAG, "🚪 User logged out on pause, ensuring overlay is hidden")
        forceHideOverlay()
    }
}
    
    override fun onStop() {
        super.onStop()
        Log.d(TAG, "📱 MainActivity onStop")
        
        // 🆕 Final check on stop
        if (!isUserLoggedIn()) {
            Log.d(TAG, "🚪 User logged out on stop, force hiding overlay")
            forceHideOverlay()
        }
    }
    
    override fun onDestroy() {
        Log.d(TAG, "📱 MainActivity onDestroy - cleaning up")
        
        // Force hide overlay on destroy
        forceHideOverlay()
        
        // Clean up handler callbacks
        handler.removeCallbacksAndMessages(null)
        
        super.onDestroy()
    }
    
    // 🆕 Handle back button press
    override fun onBackPressed() {
        if (isOverlayVisible) {
            Log.d(TAG, "⬅️ Back button pressed with overlay visible")
            // Don't allow back press when overlay is showing
            return
        }
        super.onBackPressed()
    }
    
    // 🆕 NEW: Lifecycle callback for app going to background
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        Log.d(TAG, "📱 User leaving app")
        
        // Check if we should show overlay (only if logged in and focus mode active)
        if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
            
            // 🔥 NEW: Check for system dialogs BEFORE showing overlay
            if (hasSystemAlertDialog(this)) {
                Log.d(TAG, "🎯 System dialog detected (file picker/etc), NOT showing overlay")
                return // Don't show overlay for internal app dialogs
            }
            
            Log.d(TAG, "🎯 User leaving during focus mode - Flutter will handle overlay")
            // Don't show overlay here - let Flutter handle it through the timer service
        }
    }
}