package com.robokedi.ai_cat_mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Ana ekran widget'i: uygulamayi sohbet veya "Bilgisayari Kumanda Et"
 * panelini dogrudan acarak baslatan iki hizli erisim dugmesi gosterir.
 * Dinamik veri gostermez, bu yuzden periyodik guncelleme
 * (updatePeriodMillis=0) planlanmaz.
 */
class CatWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cat_widget).apply {
                val chatIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("catwidget://open?screen=chat"),
                )
                setOnClickPendingIntent(R.id.widget_btn_chat, chatIntent)

                val remoteIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("catwidget://open?screen=remote"),
                )
                setOnClickPendingIntent(R.id.widget_btn_remote, remoteIntent)

                val openAppIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_header, openAppIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
