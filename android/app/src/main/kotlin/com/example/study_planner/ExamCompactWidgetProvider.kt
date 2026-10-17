package com.example.study_planner

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ExamCompactWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.exam_widget_compact)
            views.setTextViewText(R.id.exam_title, widgetData.getString("exam_title", "Daily Tracker") ?: "Daily Tracker")
            views.setTextViewText(R.id.exam_days, widgetData.getString("exam_days", "Open app to sync exams") ?: "Open app to sync exams")
            views.setProgressBar(R.id.exam_progress, 100, widgetData.getInt("exam_progress", 0), false)
            views.setTextViewText(R.id.exam_progress_label, widgetData.getString("exam_progress_label", "No syllabus yet") ?: "No syllabus yet")
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pending = PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}