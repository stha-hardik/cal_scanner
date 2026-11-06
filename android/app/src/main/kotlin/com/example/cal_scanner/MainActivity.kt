package com.example.cal_scanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cal_ai/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    CalWidgetStore.save(applicationContext, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    CalWidgetUpdater.updateAll(applicationContext)
                    result.success(null)
                } else if (call.method == "theme") {
                    val t = (call.arguments as? Map<*, *>)?.get("theme") as? String ?: "system"
                    CalWidgetStore.saveTheme(applicationContext, t)
                    CalWidgetUpdater.updateAll(applicationContext)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
