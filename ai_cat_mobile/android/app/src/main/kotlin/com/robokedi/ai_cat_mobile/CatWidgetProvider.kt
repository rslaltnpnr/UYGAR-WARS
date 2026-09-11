package com.robokedi.ai_cat_mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Ana ekran widget'i: uygulamayi sohbet veya "Bilgisayari Kumanda Et"
 * panelini dogrudan acarak baslatan iki hizli erisim dugmesi, ve eslesik
 * bilgisayarin son bilinen baglanti durumunu gosterir. Bu durum verisi
 * uygulama acikken calisan mevcut 45sn'lik uyari yoklamasindan
 * (HomeScreen._pollForDesktopAlerts) gelir - widget'in kendisi arka
 * planda ag istegi yapmaz, bu yuzden periyodik guncelleme
 * (updatePeriodMillis=0) planlanmaz; veri yalnizca Dart tarafi
 * HomeWidget.updateWidget() cagirdiginda tazelenir.
 */
class CatWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val profileName = widgetData.getString("widget_profile_name", null)
        val connectionStatus = widgetData.getString("widget_connection_status", null)

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

                when {
                    profileName.isNullOrEmpty() -> {
                        setTextViewText(
                            R.id.widget_status,
                            context.getString(R.string.widget_status_no_profile),
                        )
                        setTextColor(R.id.widget_status, Color.parseColor("#9A9AA5"))
                    }
                    connectionStatus == "connected" -> {
                        setTextViewText(
                            R.id.widget_status,
                            context.getString(R.string.widget_status_connected, profileName),
                        )
                        setTextColor(R.id.widget_status, Color.parseColor("#8CFF8C"))
                    }
                    connectionStatus == "disconnected" -> {
                        setTextViewText(
                            R.id.widget_status,
                            context.getString(R.string.widget_status_disconnected, profileName),
                        )
                        setTextColor(R.id.widget_status, Color.parseColor("#9A9AA5"))
                    }
                    else -> {
                        setTextViewText(
                            R.id.widget_status,
                            context.getString(R.string.widget_status_unknown),
                        )
                        setTextColor(R.id.widget_status, Color.parseColor("#9A9AA5"))
                    }
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
