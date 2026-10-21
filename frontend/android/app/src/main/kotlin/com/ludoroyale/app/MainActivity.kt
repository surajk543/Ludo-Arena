package com.ludoroyale.app

import android.annotation.SuppressLint
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_ID_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidId" -> result.success(androidId())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * ANDROID_ID, used only to restore this device's account after a
     * reinstall (lib/core/device/device_identity.dart validates it). Since
     * Android 8 it is scoped to the app signing key and user and survives
     * reinstalls; before that it is shared with every app, so null is
     * returned and the app keeps its guest-secret behaviour.
     */
    @SuppressLint("HardwareIds")
    private fun androidId(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        return try {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        } catch (e: Exception) {
            null
        }
    }

    private companion object {
        const val DEVICE_ID_CHANNEL = "ludo_royale/device_id"
    }
}
