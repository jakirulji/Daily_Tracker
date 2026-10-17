package com.example.study_planner

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ExamDetailedWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.exam_widget_detailed)
            views.setTextViewText(R.id.exam_title, widgetData.getString("exam_title", "Daily Tracker") ?: "Daily Tracker")
            views.setTextViewText(R.id.exam_days, widgetData.getString("exam_days", "Open app to sync exams") ?: "Open app to sync exams")
            views.setProgressBar(R.id.exam_progress, 100, widgetData.getInt("exam_progress", 0), false)
            views.setTextViewText(R.id.exam_progress_label, widgetData.getString("exam_progress_label", "No syllabus yet") ?: "No syllabus yet")
            val ids = intArrayOf(R.id.subject_0, R.id.subject_1, R.id.subject_2)
            val progressIds = intArrayOf(R.id.subject_progress_0, R.id.subject_progress_1, R.id.subject_progress_2)
            for (i in 0..2) {
                val name = widgetData.getString("subject_$i", "") ?: ""
                views.setTextViewText(ids[i], name)
                views.setProgressBar(progressIds[i], 100, widgetData.getInt("subject_progress_$i", 0), false)
                views.setViewVisibility(ids[i], if (name.isBlank()) android.view.View.GONE else android.view.View.VISIBLE)
                views.setViewVisibility(progressIds[i], if (name.isBlank()) android.view.View.GONE else android.view.View.VISIBLE)
            }
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pending = PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}