package com.example.coaching_institute_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Register all auto plugins (including BetterPlayer)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // If you still need manual WebView plugin registration, keep this line:
        flutterEngine.plugins.add(WebViewFlutterPlugin())

        super.configureFlutterEngine(flutterEngine)
    }
}


