package com.example.study_planner

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Attention mode = Do Not Disturb in "Priority only" mode where only calls
 * (from anyone, plus repeat callers) and alarms are allowed.
 *
 * Safety rules implemented here:
 *  - the user's previous DND filter AND policy are saved and restored on disable
 *  - an AlarmManager alarm always turns the mode off at the end time
 *  - status() self-heals: expired end time, or user turned DND off by hand
 *  - "pomodoro" owned sessions are only turned off by "pomodoro"
 */
object AttentionCore {
    private const val PREFS = "attention_state"
    const val ACTION_END = "com.example.study_planner.ATTENTION_END"

    private fun sp(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun nm(c: Context) = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun hasAccess(c: Context): Boolean =
        Build.VERSION.SDK_INT >= 23 && nm(c).isNotificationPolicyAccessGranted

    private fun alarmIntent(c: Context): PendingIntent {
        val i = Intent(c, AttentionEndReceiver::class.java).setAction(ACTION_END)
        return PendingIntent.getBroadcast(c, 7001, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun scheduleEnd(c: Context, endAt: Long) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = alarmIntent(c)
        am.cancel(pi)
        if (endAt <= 0) return
        try {
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endAt, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endAt, pi)
            }
        } catch (e: Exception) {
            try { am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endAt, pi) } catch (_: Exception) {}
        }
    }

    private fun cancelEnd(c: Context) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(alarmIntent(c))
    }

    /** Turns Attention mode on (or updates owner / end time if already on). */
    fun enable(c: Context, by: String, endAt: Long): Map<String, Any?> {
        if (!hasAccess(c)) return mapOf("ok" to false, "reason" to "no_access")
        val s = sp(c)
        val n = nm(c)
        if (s.getBoolean("active", false)) {
            // Already on. A pomodoro request never steals a manual session.
            if (by == "pomodoro" && s.getString("by", "manual") == "manual") {
                return mapOf("ok" to true, "kept" to true)
            }
            s.edit().putString("by", by).putLong("endAt", endAt).apply()
            scheduleEnd(c, endAt)
            return mapOf("ok" to true)
        }
        val p = n.notificationPolicy
        val e = s.edit()
            .putBoolean("active", true)
            .putString("by", by)
            .putLong("endAt", endAt)
            .putInt("prevFilter", n.currentInterruptionFilter)
            .putInt("prevCats", p.priorityCategories)
            .putInt("prevCalls", p.priorityCallSenders)
            .putInt("prevMsgs", p.priorityMessageSenders)
            .putInt("prevFx", p.suppressedVisualEffects)
        e.apply()

        var cats = NotificationManager.Policy.PRIORITY_CATEGORY_CALLS or
            NotificationManager.Policy.PRIORITY_CATEGORY_REPEAT_CALLERS
        var fx = p.suppressedVisualEffects
        if (Build.VERSION.SDK_INT >= 28) {
            cats = cats or NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS
            // Blocked notifications must not wake the screen or pop up on top of the app.
            fx = NotificationManager.Policy.SUPPRESSED_EFFECT_SCREEN_ON or
                NotificationManager.Policy.SUPPRESSED_EFFECT_PEEK or
                NotificationManager.Policy.SUPPRESSED_EFFECT_AMBIENT or
                NotificationManager.Policy.SUPPRESSED_EFFECT_LIGHTS
        }
        n.setNotificationPolicy(
            NotificationManager.Policy(
                cats,
                NotificationManager.Policy.PRIORITY_SENDERS_ANY,
                NotificationManager.Policy.PRIORITY_SENDERS_ANY,
                fx
            )
        )
        n.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        scheduleEnd(c, endAt)
        return mapOf("ok" to true)
    }

    /**
     * Turns Attention mode off. by="force" always works (alarm, user tapping Off);
     * by="pomodoro" only works if the session is owned by pomodoro.
     */
    fun disable(c: Context, by: String): Map<String, Any?> {
        val s = sp(c)
        if (!s.getBoolean("active", false)) return mapOf("ok" to true, "was" to false)
        if (by == "pomodoro" && s.getString("by", "manual") != "pomodoro") {
            return mapOf("ok" to true, "kept" to true)
        }
        restore(c, s)
        return mapOf("ok" to true, "was" to true)
    }

    private fun restore(c: Context, s: android.content.SharedPreferences, skipFilter: Boolean = false) {
        cancelEnd(c)
        try {
            if (hasAccess(c)) {
                val n = nm(c)
                n.setNotificationPolicy(
                    NotificationManager.Policy(
                        s.getInt("prevCats", 0),
                        s.getInt("prevCalls", NotificationManager.Policy.PRIORITY_SENDERS_ANY),
                        s.getInt("prevMsgs", NotificationManager.Policy.PRIORITY_SENDERS_ANY),
                        s.getInt("prevFx", 0)
                    )
                )
                if (!skipFilter) {
                    n.setInterruptionFilter(s.getInt("prevFilter", NotificationManager.INTERRUPTION_FILTER_ALL))
                }
            }
        } catch (_: Exception) {
        }
        s.edit().putBoolean("active", false).remove("endAt").remove("by").apply()
    }

    /** Used by the alarm and by boot: expire a session whose end time has passed. */
    fun expireIfDue(c: Context) {
        val s = sp(c)
        if (!s.getBoolean("active", false)) return
        val end = s.getLong("endAt", 0)
        if (end in 1..System.currentTimeMillis()) restore(c, s)
        else if (end > 0) scheduleEnd(c, end) // after reboot the alarm is gone: set it again
    }

    fun forceOff(c: Context) {
        val s = sp(c)
        if (s.getBoolean("active", false)) restore(c, s)
    }

    fun status(c: Context): Map<String, Any?> {
        val s = sp(c)
        val access = hasAccess(c)
        if (s.getBoolean("active", false)) {
            val end = s.getLong("endAt", 0)
            if (end in 1..System.currentTimeMillis()) {
                restore(c, s)
            } else if (access && nm(c).currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL) {
                // The user switched Do Not Disturb off by hand: respect that, restore the policy only.
                restore(c, s, skipFilter = true)
            } else if (!access) {
                s.edit().putBoolean("active", false).apply()
            }
        }
        return mapOf(
            "access" to access,
            "active" to s.getBoolean("active", false),
            "by" to s.getString("by", ""),
            "endAt" to s.getLong("endAt", 0)
        )
    }
}
