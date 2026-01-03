package com.signature.coachinginstitute

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
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
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.*

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
    
    // Track force hide state
    private var isForceHiding = false
    private var isAppsListExpanded = false
    
    // Store allowed apps data
    private var allowedAppsData: String = "[]"
    
    // App monitoring
    private var lastForegroundPackage: String? = null
    private var wasInAllowedApp = false
    
    // 🔥 LOCK-BASED SUPPRESSION SYSTEM
    private var isInAllowedAppLock = false
    private var currentAllowedAppPackage: String? = null
    private var currentAllowedAppName: String? = null
    private var allowedAppExitTime: Long = 0
    private val ALLOWED_APP_EXIT_GRACE_PERIOD = 500L // 0.5 second grace period
    
    // Foreground app monitoring (improved)
    private var foregroundChecker: ScheduledFuture<*>? = null
    private val executor = Executors.newSingleThreadScheduledExecutor()
    
    // Track state
    private var isMonitoring = false
    private var currentDetectedPackage: String = ""
    private var lastRealDetectionTime: Long = 0
    private var detectionHistory = mutableListOf<String>()
    private val MAX_HISTORY = 10
    
    // Constants
    private val MONITORING_INTERVAL = 800L // Check every 800ms for faster response
    private val MONITORING_RESTART_DELAY = 1000L // Delay before restarting monitoring
    
    // 🔥 NEW: Exit detection tracking
    private var isExitingAllowedApp = false
    private var lastExitCheckTime: Long = 0
    private var consecutiveAllowedAppChecks = 0
    private var lastKnownNonAllowedApp: String? = null
    
    // 🔥 NEW: App lifecycle tracking
    private var isAppInForeground = true
    private var lastBackgroundTime: Long = 0
    private val appBackgroundThreshold = 1000L // 1 second threshold
    
    // 🔥 NEW: False detection prevention
    private var falseDetectionCount = 0
    private val MAX_FALSE_DETECTION_THRESHOLD = 5
    private var lastValidDetection: String? = null

    @SuppressLint("ClickableViewAccessibility")
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        // Register auto plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Register WebView plugin
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
                    val success = forceHideOverlay()
                    result.success(success)
                }
                "checkOverlayPermission" -> {
                    result.success(checkOverlayPermission())
                }
                "isOverlayShowing" -> {
                    result.success(isOverlayVisible)
                }
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
                    val success = refreshAllowedAppsInOverlay()
                    result.success(success)
                }
                "getCurrentForegroundApp" -> {
                    val app = getCurrentForegroundAppReliable()
                    result.success(app)
                }
                "checkUsageStatsPermission" -> {
                    result.success(checkUsageStatsPermission())
                }
                "openUsageAccessSettings" -> {
                    openUsageAccessSettings()
                    result.success(true)
                }
                "startForegroundMonitoring" -> {
                    startReliableAppMonitoring()
                    result.success(true)
                }
                "stopForegroundMonitoring" -> {
                    stopReliableAppMonitoring()
                    result.success(true)
                }
                "resetAllowedAppLock" -> {
                    resetAllowedAppLock()
                    result.success(true)
                }
                // 🔥 NEW: Get current allowed app info
                "getCurrentAllowedAppInfo" -> {
                    val info = hashMapOf<String, Any?>(
                        "isInAllowedApp" to isInAllowedAppLock,
                        "packageName" to currentAllowedAppPackage,
                        "appName" to currentAllowedAppName
                    )
                    result.success(info)
                }
                // 🔥 NEW: Force check app status
                "forceCheckAppStatus" -> {
                    val currentPackage = getCurrentForegroundAppReliable()
                    result.success(currentPackage)
                }
                // 🔥 NEW: Force show overlay
                "forceShowOverlay" -> {
                    val message = call.argument<String>("message") ?: "You are in focus mode, focus on studies"
                    val success = showOverlay(message)
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
    
    // Check Usage Stats Permission
    private fun checkUsageStatsPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
            mode == AppOpsManager.MODE_ALLOWED
        } else {
            true
        }
    }
    
    // Open Usage Access Settings
    private fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
    
    private fun showOverlay(message: String?): Boolean {
        Log.d(TAG, "🎯 Attempting to show overlay")
        
        // Check if user is logged in and focus mode is active
        if (!isUserLoggedIn()) {
            Log.w(TAG, "⚠️ Cannot show overlay: User not logged in")
            return false
        }
        
        if (!isFocusModeActive()) {
            Log.w(TAG, "⚠️ Cannot show overlay: Focus mode not active")
            return false
        }
        
        // 🔥 Don't show overlay if we're in allowed app lock
        if (isInAllowedAppLock) {
            Log.d(TAG, "🔒 Overlay suppressed: In allowed app lock for $currentAllowedAppPackage")
            return false
        }
        
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
                
                // Make overlay clickable but allow touches on interactive elements
                overlayView!!.setOnTouchListener { _, event ->
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            // Allow click on interactive elements, block others
                            val returnButton = overlayView!!.findViewById<Button>(R.id.return_button)
                            val allowedAppsHeader = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_header)
                            val allowedAppsList = overlayView!!.findViewById<LinearLayout>(R.id.allowed_apps_list)
                            
                            val returnRect = android.graphics.Rect()
                            val headerRect = android.graphics.Rect()
                            returnButton.getGlobalVisibleRect(returnRect)
                            allowedAppsHeader.getGlobalVisibleRect(headerRect)
                            
                            var isTouchOnAllowedApp = false
                            if (isAppsListExpanded) {
                                for (i in 0 until allowedAppsList.childCount) {
                                    val child = allowedAppsList.getChildAt(i)
                                    val childRect = android.graphics.Rect()
                                    child.getGlobalVisibleRect(childRect)
                                    if (childRect.contains(event.rawX.toInt(), event.rawY.toInt())) {
                                        isTouchOnAllowedApp = true
                                        break
                                    }
                                }
                            }
                            
                            return@setOnTouchListener !(returnRect.contains(event.rawX.toInt(), event.rawY.toInt()) ||
                                headerRect.contains(event.rawX.toInt(), event.rawY.toInt()) ||
                                isTouchOnAllowedApp)
                        }
                    }
                    false
                }
                
                // Set layout parameters - IMPORTANT: Make it overlay on everything
                val params = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams(
                        WindowManager.LayoutParams.MATCH_PARENT,
                        WindowManager.LayoutParams.MATCH_PARENT,
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
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
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
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
                
                // Start reliable app monitoring when overlay is shown
                startReliableAppMonitoring()
                
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
    
    // 🔥 Load allowed apps into the overlay list - FIXED app launch callback
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
                            // 🔥 Set allowed app lock BEFORE launching
                            setAllowedAppLock(packageName, appName)
                            
                            // Hide overlay temporarily
                            hideOverlay()
                            
                            // Give time for overlay to hide
                            handler.postDelayed({
                                // Try to launch the app
                                val intent = packageManager.getLaunchIntentForPackage(packageName)
                                if (intent != null) {
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(intent)
                                    
                                    // 🔥 Send as Map<String, Any>
                                    val appData = hashMapOf<String, Any>(
                                        "appName" to appName,
                                        "packageName" to packageName
                                    )
                                    
                                    // Notify Flutter that app was launched
                                    flutterEngine?.dartExecutor?.binaryMessenger?.let {
                                        MethodChannel(it, CHANNEL).invokeMethod("onAppLaunch", appData)
                                    }
                                    
                                    Log.d(TAG, "✅ App launched with lock: $appName")
                                    
                                    // Stop monitoring while in allowed app
                                    stopReliableAppMonitoring()
                                    
                                    // Schedule restart of monitoring after a delay
                                    handler.postDelayed({
                                        if (isInAllowedAppLock) {
                                            // Restart monitoring but with suppressed overlay
                                            startReliableAppMonitoring()
                                        }
                                    }, MONITORING_RESTART_DELAY)
                                    
                                } else {
                                    Log.e(TAG, "❌ Could not find launch intent for: $packageName")
                                    // Reset lock if app couldn't be opened
                                    resetAllowedAppLock()
                                    // Show overlay again if app couldn't be opened
                                    showOverlay("Could not open $appName")
                                }
                            }, 200)
                            
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error launching app: ${e.message}", e)
                            // Reset lock on error
                            resetAllowedAppLock()
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
    
    // 🔥 SET ALLOWED APP LOCK - Complete suppression while in allowed app
    @SuppressLint("StaticFieldLeak")
    private fun setAllowedAppLock(packageName: String, appName: String) {
        // Run on UI thread to be safe
        handler.post {
            Log.d(TAG, "🔒 Setting allowed app lock for: $appName ($packageName)")
            isInAllowedAppLock = true
            currentAllowedAppPackage = packageName
            currentAllowedAppName = appName
            wasInAllowedApp = true
            
            // 🔥 Reset exit detection tracking
            isExitingAllowedApp = false
            consecutiveAllowedAppChecks = 0
            falseDetectionCount = 0
            lastValidDetection = packageName
            
            // Hide overlay immediately if it's showing
            if (isOverlayVisible) {
                hideOverlay()
            }
            
            // Update SharedPreferences
            sharedPreferences?.edit()?.apply {
                putBoolean("flutter.in_allowed_app", true)
                putString("flutter.current_allowed_app", packageName)
                putString("flutter.current_allowed_app_name", appName)
                apply()
            }
            
            // 🔥 Notify Flutter about allowed app entry
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                val data = hashMapOf<String, Any>(
                    "packageName" to packageName,
                    "appName" to appName,
                    "action" to "entered"
                )
                MethodChannel(it, CHANNEL).invokeMethod("onAllowedAppStatusChanged", data)
            }
        }
    }
    
    // 🔥 RESET ALLOWED APP LOCK
    @SuppressLint("StaticFieldLeak")
    private fun resetAllowedAppLock() {
        // Run on UI thread to be safe
        handler.post {
            Log.d(TAG, "🔓 Resetting allowed app lock")
            
            val wasLocked = isInAllowedAppLock
            val previousPackage = currentAllowedAppPackage
            val previousName = currentAllowedAppName
            
            isInAllowedAppLock = false
            currentAllowedAppPackage = null
            currentAllowedAppName = null
            allowedAppExitTime = System.currentTimeMillis()
            
            // 🔥 Reset exit detection tracking
            isExitingAllowedApp = false
            consecutiveAllowedAppChecks = 0
            falseDetectionCount = 0
            lastValidDetection = null
            
            // Update SharedPreferences
            sharedPreferences?.edit()?.apply {
                putBoolean("flutter.in_allowed_app", false)
                remove("flutter.current_allowed_app")
                remove("flutter.current_allowed_app_name")
                apply()
            }
            
            // 🔥 Notify Flutter about allowed app exit
            if (wasLocked && previousPackage != null) {
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    val data = hashMapOf<String, Any>(
                        "packageName" to previousPackage,
                        "appName" to (previousName ?: "Unknown App"),
                        "action" to "exited"
                    )
                    MethodChannel(it, CHANNEL).invokeMethod("onAllowedAppStatusChanged", data)
                }
            }
        }
    }
    
    // 🔥 NEW: Check if package is Home/Recents
    private fun isHomeOrRecents(packageName: String): Boolean {
        return packageName.contains("launcher") || 
               packageName.contains("systemui") ||
               packageName.contains("android.system") ||
               packageName.contains("com.android.systemui") ||
               packageName == "com.google.android.apps.nexuslauncher" ||
               packageName == "com.sec.android.app.launcher" ||
               packageName == "com.huawei.android.launcher" ||
               packageName == "com.miui.home" ||
               packageName == "com.oneplus.launcher" ||
               packageName == "com.google.android.apps.nexuslauncher" ||
               packageName.contains("home") ||
               packageName.contains("recent") ||
               packageName.contains("recents")
    }
    
    // 🔥 RELIABLE app monitoring with ENHANCED EXIT DETECTION
    private fun startReliableAppMonitoring() {
        Log.d(TAG, "🔄 Starting RELIABLE app monitoring (${MONITORING_INTERVAL}ms interval)")
        
        stopReliableAppMonitoring()
        
        isMonitoring = true
        foregroundChecker = executor.scheduleAtFixedRate({
            try {
                if (!isMonitoring) return@scheduleAtFixedRate
                
                // Get current app with reliable detection
                val currentPackage = getCurrentForegroundAppReliable()
                
                if (currentPackage == null || currentPackage.isEmpty()) {
                    return@scheduleAtFixedRate
                }
                
                // 🔥 ENHANCED EXIT DETECTION FOR ALLOWED APPS
                if (isInAllowedAppLock) {
                    handleAllowedAppMonitoring(currentPackage)
                } else {
                    // Normal monitoring for non-allowed apps
                    handleNonAllowedAppMonitoring(currentPackage)
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in reliable app monitoring: ${e.message}")
            }
        }, 0, MONITORING_INTERVAL, TimeUnit.MILLISECONDS)
    }
    
    // 🔥 HANDLE MONITORING WHILE IN ALLOWED APP (with ENHANCED exit detection)
    private fun handleAllowedAppMonitoring(currentPackage: String) {
        // Check if we're still in the allowed app
        if (currentPackage == currentAllowedAppPackage) {
            // Still in the allowed app
            consecutiveAllowedAppChecks = 0
            isExitingAllowedApp = false
            falseDetectionCount = 0
            lastValidDetection = currentPackage
            lastExitCheckTime = System.currentTimeMillis()
            Log.d(TAG, "✅ Still in allowed app: $currentPackage")
            return
        }
        
        // 🔥 CHECK FOR FALSE DETECTION FIRST
        // If we're detecting our own app but we should be in allowed app, it's likely false
        if (currentPackage == packageName && currentAllowedAppPackage != null) {
            falseDetectionCount++
            Log.d(TAG, "⚠️ FALSE DETECTION #$falseDetectionCount: Still in $currentAllowedAppPackage, not our app")
            
            // If too many false detections in a row, trust the allowed app
            if (falseDetectionCount >= MAX_FALSE_DETECTION_THRESHOLD) {
                Log.d(TAG, "✅ Ignoring false detections, staying in allowed app lock")
                falseDetectionCount = 0
                consecutiveAllowedAppChecks = 0
                return
            }
            
            // Only treat as exit if we have multiple detections AND app is actually in background
            if (falseDetectionCount >= 3 && !isAppInForeground) {
                Log.d(TAG, "✅ CONFIRMED: Returned to our app from allowed app")
                handleConfirmedExit(currentPackage)
            }
            return
        }
        
        // 🔥 Check if user went to home/recents
        val isHomeScreen = isHomeOrRecents(currentPackage)
        
        if (isHomeScreen) {
            // User went to home or recents
            consecutiveAllowedAppChecks++
            Log.d(TAG, "🏠 Home/Recents detected: Check $consecutiveAllowedAppChecks")
            
            if (consecutiveAllowedAppChecks >= 2) {
                Log.d(TAG, "✅ CONFIRMED: Left allowed app for Home/Recents")
                handleConfirmedExit(currentPackage)
            }
            return
        }
        
        // We're NOT in the allowed app anymore AND not in our app or home
        consecutiveAllowedAppChecks++
        falseDetectionCount = 0 // Reset false detection count for real app changes
        
        Log.d(TAG, "🚨 Exit detection: Check $consecutiveAllowedAppChecks - Was in $currentAllowedAppPackage, now in $currentPackage")
        
        // Check if user is going to another allowed app
        val isAnotherAllowedApp = isAppAllowed(currentPackage)
        
        // 🔥 Only need 2 detections for switching to other apps
        if (consecutiveAllowedAppChecks >= 2) {
            Log.d(TAG, "✅ CONFIRMED: Left allowed app $currentAllowedAppPackage → $currentPackage")
            handleConfirmedExit(currentPackage)
        }
    }
    
    // 🔥 NEW: Handle confirmed exit separately
    private fun handleConfirmedExit(destinationPackage: String) {
        handler.post {
            val isAnotherAllowedApp = isAppAllowed(destinationPackage)
            val isOurApp = destinationPackage == packageName
            val isHomeScreen = isHomeOrRecents(destinationPackage)
            
            if (isOurApp) {
                // User genuinely returned to our app
                Log.d(TAG, "✅ User GENUINELY returned to our app from allowed app")
                
                // 🔥 RESET THE LOCK IMMEDIATELY when returning to our app
                resetAllowedAppLock()
                
                // Show overlay if focus mode is active
                if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
                    showOverlay("Welcome back! Focus mode is active")
                }
                
            } else if (isHomeScreen) {
                // User went to home or recents
                Log.d(TAG, "🏠 User went to Home/Recents from allowed app")
                
                // 🔥 RESET LOCK when going to home/recents
                resetAllowedAppLock()
                
                // Show overlay
                if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
                    showOverlay("You left the allowed app. Focus mode is active")
                }
                
            } else if (isAnotherAllowedApp) {
                // User switched to another allowed app
                Log.d(TAG, "🔄 User switched to another allowed app: $destinationPackage")
                
                // Get app name
                val newAppName = try {
                    val allowedAppsJson = getAllowedApps()
                    val allowedApps = JSONArray(allowedAppsJson)
                    var foundName: String? = null
                    
                    for (i in 0 until allowedApps.length()) {
                        val app = allowedApps.getJSONObject(i)
                        if (app.getString("packageName") == destinationPackage) {
                            foundName = app.getString("appName")
                            break
                        }
                    }
                    foundName ?: "Unknown App"
                } catch (e: Exception) {
                    "Unknown App"
                }
                
                // Transfer lock to new app
                setAllowedAppLock(destinationPackage, newAppName)
                
            } else {
                // User went to a NON-ALLOWED app
                Log.d(TAG, "🚨 User went to NON-ALLOWED app: $destinationPackage")
                
                // 🔥 RESET LOCK when going to non-allowed app
                resetAllowedAppLock()
                
                if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
                    // Try to get app name
                    val appName = try {
                        val appInfo = packageManager.getApplicationInfo(destinationPackage, 0)
                        packageManager.getApplicationLabel(appInfo).toString()
                    } catch (e: Exception) {
                        destinationPackage
                    }
                    showOverlay("Cannot use $appName during focus mode")
                }
            }
            
            // Reset exit detection tracking
            consecutiveAllowedAppChecks = 0
            isExitingAllowedApp = false
            falseDetectionCount = 0
        }
    }
    
    // 🔥 HANDLE MONITORING FOR NON-ALLOWED APPS
    private fun handleNonAllowedAppMonitoring(currentPackage: String) {
        // Check if app changed
        if (currentPackage != currentDetectedPackage) {
            Log.d(TAG, "🔄 App changed: $currentDetectedPackage → $currentPackage")
            
            // Store previous package
            val previousPackage = currentDetectedPackage
            
            // Update current package
            currentDetectedPackage = currentPackage
            
            // Add to history
            detectionHistory.add(currentPackage)
            if (detectionHistory.size > MAX_HISTORY) {
                detectionHistory.removeAt(0)
            }
            
            // Update last detection time
            lastRealDetectionTime = System.currentTimeMillis()
            
            // Check if we need to show overlay
            checkAndShowOverlayForDetectedApp(currentPackage, previousPackage)
        } else {
            // Same app
            lastForegroundPackage = currentPackage
        }
    }
    
    // 🔥 Check if overlay should be shown for detected app
    private fun checkAndShowOverlayForDetectedApp(currentPackage: String, previousPackage: String?) {
        val isCurrentOurApp = currentPackage == packageName
        val isCurrentAllowed = isAppAllowed(currentPackage)
        val isHomeScreen = isHomeOrRecents(currentPackage)
        
        // 🔥 Show overlay ONLY if:
        // 1. Current app is NOT our app
        // 2. Current app is NOT allowed
        // 3. We're not already showing overlay
        // 4. We're NOT in allowed app lock
        // 5. Not home screen (home screen should trigger overlay if we're not in allowed app)
        if (!isCurrentOurApp && !isCurrentAllowed && !isInAllowedAppLock && !isHomeScreen) {
            Log.d(TAG, "🚫 Blocking non-allowed app: $currentPackage")
            
            if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
                handler.post {
                    // Try to get app name for better message
                    val appName = try {
                        val appInfo = packageManager.getApplicationInfo(currentPackage, 0)
                        packageManager.getApplicationLabel(appInfo).toString()
                    } catch (e: Exception) {
                        currentPackage
                    }
                    showOverlay("Cannot use $appName during focus mode")
                }
            }
        } else if (isHomeScreen && !isInAllowedAppLock && isUserLoggedIn() && isFocusModeActive()) {
            // User went to home screen - show overlay after delay
            Log.d(TAG, "🏠 Home screen detected, showing overlay")
            handler.postDelayed({
                if (!isOverlayVisible && !isInAllowedAppLock) {
                    showOverlay("Focus mode is active")
                }
            }, 500)
        } else if (isCurrentAllowed && !isInAllowedAppLock) {
            // 🔥 Entered allowed app without going through overlay
            // This can happen if user opens allowed app directly
            Log.d(TAG, "🔒 Entered allowed app directly: $currentPackage")
            
            val appName = try {
                val allowedAppsJson = getAllowedApps()
                val allowedApps = JSONArray(allowedAppsJson)
                var foundName: String? = null
                
                for (i in 0 until allowedApps.length()) {
                    val app = allowedApps.getJSONObject(i)
                    if (app.getString("packageName") == currentPackage) {
                        foundName = app.getString("appName")
                        break
                    }
                }
                foundName ?: "Unknown App"
            } catch (e: Exception) {
                "Unknown App"
            }
            setAllowedAppLock(currentPackage, appName)
        }
    }
    
    private fun stopReliableAppMonitoring() {
        try {
            isMonitoring = false
            foregroundChecker?.cancel(true)
            foregroundChecker = null
            Log.d(TAG, "🛑 Stopped reliable app monitoring")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping app monitoring: ${e.message}")
        }
    }
    
    // 🔥 RELIABLE foreground app detection with IMPROVED filtering
    private fun getCurrentForegroundAppReliable(): String? {
        try {
            // 🔥 When we're in allowed app lock, be extra careful about false detections
            if (isInAllowedAppLock && currentAllowedAppPackage != null) {
                return getForegroundAppWithAllowedAppCheck()
            }
            
            // Normal detection for non-locked state
            return getForegroundAppNormal()
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in getCurrentForegroundAppReliable: ${e.message}")
            return null
        }
    }
    
    // 🔥 NEW: Special detection when in allowed app lock
    private fun getForegroundAppWithAllowedAppCheck(): String? {
        try {
            // Use only the most reliable methods when in allowed app
            val detectedApps = mutableListOf<String?>()
            
            // Method 1: UsageStatsManager (most reliable for actual app usage)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && checkUsageStatsPermission()) {
                val usageStatsResult = getForegroundAppFromUsageStatsEnhanced()
                if (usageStatsResult != null) {
                    detectedApps.add(usageStatsResult)
                }
            }
            
            // Method 2: Activity Manager (but filter out our app if we're in allowed app)
            val activityManagerResult = getForegroundAppFromActivityManagerEnhanced()
            if (activityManagerResult != null) {
                detectedApps.add(activityManagerResult)
            }
            
            // Find the most common non-null result
            val validResults = detectedApps.filterNotNull().filter { it.isNotEmpty() }
            
            if (validResults.isNotEmpty()) {
                // Return the most frequent result
                val frequencyMap = mutableMapOf<String, Int>()
                for (result in validResults) {
                    frequencyMap[result] = frequencyMap.getOrDefault(result, 0) + 1
                }
                
                val mostFrequent = frequencyMap.maxByOrNull { it.value }?.key
                
                // 🔥 CRITICAL: If we're in allowed app lock and detect our own app,
                // verify it's not a false detection
                if (mostFrequent == packageName && isInAllowedAppLock) {
                    Log.d(TAG, "⚠️ SUSPICIOUS: Detected our app while in allowed app lock")
                    
                    // Check if we have any other results
                    val otherApps = validResults.filter { it != packageName }
                    if (otherApps.isNotEmpty()) {
                        // Trust the other apps more
                        val otherFreqMap = mutableMapOf<String, Int>()
                        for (result in otherApps) {
                            otherFreqMap[result] = otherFreqMap.getOrDefault(result, 0) + 1
                        }
                        return otherFreqMap.maxByOrNull { it.value }?.key ?: mostFrequent
                    }
                }
                
                return mostFrequent
            }
            
            // If no detection, assume we're still in the allowed app
            return currentAllowedAppPackage
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in getForegroundAppWithAllowedAppCheck: ${e.message}")
            return currentAllowedAppPackage
        }
    }
    
    // 🔥 NEW: Normal detection for non-locked state
    private fun getForegroundAppNormal(): String? {
        try {
            // Try all detection methods
            val detectedApps = mutableListOf<String?>()
            
            // Method 1: UsageStatsManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && checkUsageStatsPermission()) {
                detectedApps.add(getForegroundAppFromUsageStatsEnhanced())
            }
            
            // Method 2: Activity Manager
            detectedApps.add(getForegroundAppFromActivityManagerEnhanced())
            
            // Method 3: Running processes
            detectedApps.add(getForegroundAppFromRunningProcessesReliable())
            
            // Find the most common non-null result
            val validResults = detectedApps.filterNotNull().filter { it.isNotEmpty() }
            
            if (validResults.isNotEmpty()) {
                // Return the most frequent result
                val frequencyMap = mutableMapOf<String, Int>()
                for (result in validResults) {
                    frequencyMap[result] = frequencyMap.getOrDefault(result, 0) + 1
                }
                
                return frequencyMap.maxByOrNull { it.value }?.key
            }
            
            return null
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in getForegroundAppNormal: ${e.message}")
            return null
        }
    }
    
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun getForegroundAppFromUsageStatsEnhanced(): String? {
        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val currentTime = System.currentTimeMillis()
            
            // Use 3-second window for better reliability
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                currentTime - 3000,
                currentTime
            )
            
            if (stats != null) {
                var mostRecent: UsageStats? = null
                
                for (usageStats in stats) {
                    if (usageStats.lastTimeUsed > 0) {
                        if (mostRecent == null || usageStats.lastTimeUsed > mostRecent.lastTimeUsed) {
                            mostRecent = usageStats
                        }
                    }
                }
                
                if (mostRecent != null) {
                    val packageName = mostRecent.packageName
                    // Filter out system apps but include launchers
                    if (!packageName.contains("android.system")) {
                        return packageName
                    }
                }
            }
        } catch (e: Exception) {
            // Silent catch
        }
        return null
    }
    
    private fun getForegroundAppFromActivityManagerEnhanced(): String? {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Try running app processes first (more reliable)
                val processes = activityManager.runningAppProcesses
                if (processes != null) {
                    for (process in processes) {
                        if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                            if (process.pkgList != null && process.pkgList.isNotEmpty()) {
                                for (pkg in process.pkgList) {
                                    if (pkg.isNotEmpty() && pkg != packageName) {
                                        // Prefer non-our-app packages when in allowed app lock
                                        return pkg
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Try app tasks as fallback
                val tasks = activityManager.appTasks
                if (tasks != null) {
                    for (task in tasks) {
                        try {
                            val taskInfo = task.taskInfo
                            if (taskInfo != null && taskInfo.topActivity != null) {
                                val pkgName = taskInfo.topActivity!!.packageName
                                if (pkgName.isNotEmpty() && pkgName != packageName) {
                                    return pkgName
                                }
                            }
                        } catch (e: Exception) {
                            continue
                        }
                    }
                }
                
            } else {
                // For older Android versions
                @Suppress("DEPRECATION")
                val runningTasks = activityManager.getRunningTasks(1)
                if (runningTasks != null && runningTasks.isNotEmpty()) {
                    val task = runningTasks[0]
                    if (task.topActivity != null) {
                        val pkgName = task.topActivity!!.packageName
                        if (pkgName.isNotEmpty() && pkgName != packageName) {
                            return pkgName
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Silent catch
        }
        return null
    }
    
    private fun getForegroundAppFromRunningProcessesReliable(): String? {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val processes = activityManager.runningAppProcesses
                if (processes != null) {
                    // Look for foreground and visible processes
                    for (process in processes) {
                        if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                            process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE) {
                            
                            if (process.pkgList != null && process.pkgList.isNotEmpty()) {
                                for (pkg in process.pkgList) {
                                    if (pkg.isNotEmpty()) {
                                        return pkg
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Silent catch
        }
        return null
    }
    
    // Check if app is allowed
    private fun isAppAllowed(packageName: String): Boolean {
        return try {
            val allowedAppsJson = getAllowedApps()
            val allowedApps = JSONArray(allowedAppsJson)
            
            for (i in 0 until allowedApps.length()) {
                val app = allowedApps.getJSONObject(i)
                val allowedPackage = app.getString("packageName")
                if (allowedPackage == packageName) {
                    return true
                }
            }
            false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking if app is allowed: ${e.message}")
            false
        }
    }
    
    // 🔥 Check if user is logged in
    private fun isUserLoggedIn(): Boolean {
        val accessToken = sharedPreferences?.getString("flutter.accessToken", null)
        val username = sharedPreferences?.getString("flutter.username", null)
        return !accessToken.isNullOrEmpty() && !username.isNullOrEmpty()
    }
    
    // 🔥 Check if focus mode is active
    private fun isFocusModeActive(): Boolean {
        return sharedPreferences?.getBoolean("flutter.is_focus_mode", false) ?: false
    }
    
    private fun hideOverlay(): Boolean {
        Log.d(TAG, "🎯 Attempting to hide overlay...")
        
        // Stop app monitoring when hiding overlay
        stopReliableAppMonitoring()
        
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
    
    // Force hide overlay with aggressive cleanup
    private fun forceHideOverlay(): Boolean {
        Log.d(TAG, "🔴 FORCE HIDING OVERLAY - AGGRESSIVE MODE")
        
        // Stop monitoring
        stopReliableAppMonitoring()
        
        // Reset allowed app lock
        resetAllowedAppLock()
        
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
                lastForegroundPackage = null
                currentDetectedPackage = ""
                detectionHistory.clear()
                lastRealDetectionTime = 0
                wasInAllowedApp = false
                
                // Clear all SharedPreferences flags
                sharedPreferences?.edit()?.apply {
                    putBoolean("flutter.overlay_visible", false)
                    putBoolean("flutter.is_focus_mode", false)
                    putBoolean("flutter.in_allowed_app", false)
                    remove("flutter.current_allowed_app")
                    remove("flutter.current_allowed_app_name")
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
            lastForegroundPackage = null
            currentDetectedPackage = ""
            detectionHistory.clear()
            lastRealDetectionTime = 0
            wasInAllowedApp = false
            isInAllowedAppLock = false
            currentAllowedAppPackage = null
            currentAllowedAppName = null
            isForceHiding = false
        }
        
        return success
    }
    
    // Refresh allowed apps in overlay
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
    
    // Update allowed apps
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
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating allowed apps: ${e.message}", e)
            false
        }
    }
    
    // Get allowed apps
    private fun getAllowedApps(): String {
        return try {
            // Load from SharedPreferences if not already loaded
            if (allowedAppsData == "[]") {
                allowedAppsData = sharedPreferences?.getString("overlay_allowed_apps", "[]") ?: "[]"
            }
            
            allowedAppsData
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting allowed apps: ${e.message}", e)
            "[]"
        }
    }
    
    // Clear allowed apps
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
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "📱 MainActivity onCreate")
        
        // Restore allowed app lock state if exists
        val wasInAllowedApp = sharedPreferences?.getBoolean("flutter.in_allowed_app", false) ?: false
        val lastAllowedApp = sharedPreferences?.getString("flutter.current_allowed_app", null)
        val lastAllowedAppName = sharedPreferences?.getString("flutter.current_allowed_app_name", null)
        
        if (wasInAllowedApp && lastAllowedApp != null) {
            Log.d(TAG, "🔄 Restoring allowed app lock for: $lastAllowedApp ($lastAllowedAppName)")
            isInAllowedAppLock = true
            currentAllowedAppPackage = lastAllowedApp
            currentAllowedAppName = lastAllowedAppName
        } else {
            currentDetectedPackage = packageName
        }
        
        lastRealDetectionTime = System.currentTimeMillis()
        isAppInForeground = true
    }
    
    override fun onResume() {
        super.onResume()
        Log.d(TAG, "📱 MainActivity onResume")
        isAppInForeground = true
        lastBackgroundTime = 0
        
        // 🔥 Check if we were in allowed app lock and now we're back
        if (isInAllowedAppLock) {
            val currentApp = getCurrentForegroundAppReliable()
            
            if (currentApp == packageName) {
                // User returned to our app from allowed app
                Log.d(TAG, "🎯 User returned to our app from allowed app")
                resetAllowedAppLock()
                
                // Show overlay if focus mode is active
                if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
                    showOverlay("Welcome back! Focus mode is active")
                }
            } else if (currentApp != null && isHomeOrRecents(currentApp)) {
                // User went to home/recents from allowed app
                Log.d(TAG, "🏠 User went to Home/Recents from allowed app")
                resetAllowedAppLock()
                
                if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible) {
                    showOverlay("You left the allowed app. Focus mode is active")
                }
            } else if (currentApp != null && currentApp != currentAllowedAppPackage) {
                // User switched to another app while we were in background
                Log.d(TAG, "🔄 User switched to another app: $currentApp")
                // Don't reset lock here - let monitoring handle it
            }
        } else {
            currentDetectedPackage = packageName
            lastForegroundPackage = packageName
            detectionHistory.clear()
            detectionHistory.add(packageName)
        }
        
        lastRealDetectionTime = System.currentTimeMillis()
        
        // Check if user is logged out
        if (!isUserLoggedIn()) {
            Log.d(TAG, "🚪 User logged out, force hiding overlay")
            forceHideOverlay()
            return
        }
        
        // Check if focus mode is active
        if (isFocusModeActive()) {
            // Start app monitoring
            startReliableAppMonitoring()
        }
    }
    
    override fun onPause() {
        super.onPause()
        Log.d(TAG, "📱 MainActivity onPause")
        isAppInForeground = false
        lastBackgroundTime = System.currentTimeMillis()
    }
    
    override fun onStop() {
        super.onStop()
        Log.d(TAG, "📱 MainActivity onStop")
        
        // Final check on stop
        if (!isUserLoggedIn()) {
            Log.d(TAG, "🚪 User logged out on stop, force hiding overlay")
            forceHideOverlay()
        }
    }
    
    override fun onDestroy() {
        Log.d(TAG, "📱 MainActivity onDestroy - cleaning up")
        
        // Force hide overlay on destroy
        forceHideOverlay()
        
        // Clean up handler callbacks and monitoring
        stopReliableAppMonitoring()
        handler.removeCallbacksAndMessages(null)
        
        super.onDestroy()
    }
    
    // Handle back button press
    override fun onBackPressed() {
        if (isOverlayVisible) {
            Log.d(TAG, "⬅️ Back button pressed with overlay visible")
            // Don't allow back press when overlay is showing
            return
        }
        super.onBackPressed()
    }
    
    // Lifecycle callback for app going to background
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        Log.d(TAG, "📱 User leaving app - onUserLeaveHint()")
        
        if (isUserLoggedIn() && isFocusModeActive() && !isOverlayVisible && !isInAllowedAppLock) {
            // User is leaving our app (not going to allowed app)
            Log.d(TAG, "🎯 User leaving app during focus mode")
            
            // Check destination after delay
            handler.postDelayed({
                val destinationApp = getCurrentForegroundAppReliable()
                
                if (destinationApp != null && destinationApp != packageName) {
                    if (isAppAllowed(destinationApp)) {
                        // User went directly to allowed app
                        Log.d(TAG, "🔒 User went directly to allowed app: $destinationApp")
                        
                        // Get app name
                        val appName = try {
                            val allowedAppsJson = getAllowedApps()
                            val allowedApps = JSONArray(allowedAppsJson)
                            var foundName: String? = null
                            
                            for (i in 0 until allowedApps.length()) {
                                val app = allowedApps.getJSONObject(i)
                                if (app.getString("packageName") == destinationApp) {
                                    foundName = app.getString("appName")
                                    break
                                }
                            }
                            foundName ?: "Unknown App"
                        } catch (e: Exception) {
                            "Unknown App"
                        }
                        
                        setAllowedAppLock(destinationApp, appName)
                    } else {
                        // User went to non-allowed app
                        Log.d(TAG, "🎯 Showing overlay for non-allowed destination: $destinationApp")
                        showOverlay("You are in focus mode, focus on studies")
                    }
                }
            }, 400)
        }
    }
}