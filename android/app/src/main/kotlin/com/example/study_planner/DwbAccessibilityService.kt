package com.example.study_planner

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent

/**
 * Receives Android window/app-switch events so DWB can react as soon as a
 * selected app becomes foreground instead of waiting for UsageStats polling.
 * This does not intercept a launch before Android starts the target app.
 */
class DwbAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        val prefs = getSharedPreferences("dwb_blocking", Context.MODE_PRIVATE)
        val strict = prefs.getBoolean("enabled", false) &&
            !prefs.getStringSet("selectedPackages", emptySet()).isNullOrEmpty()
        val gentle = !prefs.getStringSet("gentlePackages", emptySet()).isNullOrEmpty()
        if (strict || gentle) {
            val intent = Intent(this, DwbSessionService::class.java)
                .setAction(DwbSessionService.ACTION_CONFIGURE_BLOCKING)
            runCatching {
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString()?.takeIf { it.isNotBlank() } ?: return
        if (pkg == packageName) return
        DwbSessionService.onAccessibilityPackageChanged(pkg)
    }

    override fun onInterrupt() = Unit
}
