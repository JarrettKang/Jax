package com.jarrett.jax

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.jarrett.jax/debug_sync"
    private var syncCommandPath: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        syncCommandPath = intent.getStringExtra("jax_sync_command")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        syncCommandPath = intent.getStringExtra("jax_sync_command")
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takeCommandPath" -> {
                    val value = syncCommandPath
                    syncCommandPath = null
                    result.success(value)
                }
                else -> result.notImplemented()
            }
        }
    }
}
