package com.example.study_planner

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fires at the end time (always turns Attention mode off) and after a reboot (re-arms or expires it). */
class AttentionEndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                AttentionCore.ACTION_END -> AttentionCore.forceOff(context)
                else -> AttentionCore.expireIfDue(context) // BOOT_COMPLETED / MY_PACKAGE_REPLACED
            }
        } catch (_: Exception) {
        }
    }
}
