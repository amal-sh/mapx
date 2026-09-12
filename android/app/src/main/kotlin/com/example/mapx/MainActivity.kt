package com.example.mapx

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ArBridge(flutterEngine).register()
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "mapx/ar_scene_view",
                ArScenePlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )
    }
}
