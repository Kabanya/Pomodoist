package com.finchforge.pomodoist

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pomodoist/app_icon")
            .setMethodCallHandler { call, result ->
                val pomo = ComponentName(packageName, "com.finchforge.pomodoist.PomoLauncher")
                val classic = ComponentName(packageName, "com.finchforge.pomodoist.ClassicLauncher")
                if (call.method == "getIcon") {
                    result.success(if (packageManager.getComponentEnabledSetting(classic) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) "classic" else "icon-light-pomo")
                } else if (call.method == "setIcon") {
                    val icon = (call.arguments as? Map<*, *>)?.get("icon") as? String
                    if (icon != "icon-light-pomo" && icon != "classic") {
                        result.error("invalid_icon", "Unsupported app icon.", null)
                    } else {
                        val selected = if (icon == "classic") classic else pomo
                        val other = if (icon == "classic") pomo else classic
                        val previousSelected = packageManager.getComponentEnabledSetting(selected)
                        val previousOther = packageManager.getComponentEnabledSetting(other)
                        try {
                            packageManager.setComponentEnabledSetting(selected, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                            packageManager.setComponentEnabledSetting(other, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                            result.success(null)
                        } catch (error: Exception) {
                            try {
                                packageManager.setComponentEnabledSetting(other, previousOther, PackageManager.DONT_KILL_APP)
                                packageManager.setComponentEnabledSetting(selected, previousSelected, PackageManager.DONT_KILL_APP)
                            } catch (_: Exception) { /* Keep at least the selected launcher enabled. */ }
                            result.error("icon_failed", error.message, null)
                        }
                    }
                } else { result.notImplemented() }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pomodoist/voice_settings")
            .setMethodCallHandler { call, result ->
                if (call.method != "openMicrophoneSettings") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                } catch (_: SecurityException) {
                    result.success(false)
                }
            }
    }
}
