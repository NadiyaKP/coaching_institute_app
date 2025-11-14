package com.example.coaching_institute_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin

class MainActivity: FlutterActivity() {

    // ✅ This is the fix: Enable Hybrid Composition Texture Mode
    override fun getRenderMode() = RenderMode.texture
    override fun getTransparencyMode() = TransparencyMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Register auto plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Register WebView plugin (if required in your setup)
        flutterEngine.plugins.add(WebViewFlutterPlugin())

        super.configureFlutterEngine(flutterEngine)
    }
}
