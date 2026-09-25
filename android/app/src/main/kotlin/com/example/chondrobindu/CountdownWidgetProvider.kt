package com.example.chondrobindu

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class CountdownWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_countdown).apply {
                val daysRemaining = widgetData.getString("days_remaining", "-- Days")
                val eventName = widgetData.getString("event_name", "Tap to set goal 🎯")

                setTextViewText(R.id.widget_days_remaining, daysRemaining)
                setTextViewText(R.id.widget_event_name, eventName)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
