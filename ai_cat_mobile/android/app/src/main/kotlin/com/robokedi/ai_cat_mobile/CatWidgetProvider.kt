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
 * Ana ekran widget'i: uygulamayi kullanicinin ayarlar panelinden sectigi
 * iki hizli erisim eylemiyle (sohbet, kumanda, hatirlatici - varsayilan
 * sohbet+kumanda) dogrudan acan iki dugme, ve eslesik bilgisayarin son
 * bilinen baglanti durumunu gosterir. Bu durum verisi uygulama acikken
 * calisan mevcut 45sn'lik uyari yoklamasindan
 * (HomeScreen._pollForDesktopAlerts) gelir - widget'in kendisi arka
 * planda ag istegi yapmaz, bu yuzden periyodik guncelleme
 * (updatePeriodMillis=0) planlanmaz; veri yalnizca Dart tarafi
 * HomeWidget.updateWidget() cagirdiginda tazelenir.
 */
class CatWidgetProvider : HomeWidgetProvider() {

    private data class SlotAction(val uriValue: String, val labelResId: Int)

    // Simge degil, yalnizca etiket + tiklama hedefi dinamik: RemoteViews'in
    // bir TextView'in drawableTop'unu calisma zamaninda degistirebilecegi
    // setTextViewCompoundDrawables(int,int,int,int,int) metodu API 31'den
    // once yok - minSdk cok daha dusuk oldugu icin (bkz. build.gradle.kts)
    // cagirmak eski cihazlarda NoSuchMethodError ile cokerdi. Simgeler bu
    // yuzden layout'taki (cat_widget.xml) konumlarina sabit kalir.
    private val slotActions = listOf(
        SlotAction("chat", R.string.widget_action_chat),
        SlotAction("remote", R.string.widget_action_remote),
        SlotAction("reminder", R.string.widget_action_reminder),
    )

    private fun slotActionFor(uriValue: String?, fallback: String) =
        slotActions.find { it.uriValue == uriValue } ?: slotActions.find { it.uriValue == fallback }!!

    private fun RemoteViews.bindSlotButton(context: Context, viewId: Int, action: SlotAction) {
        setTextViewText(viewId, context.getString(action.labelResId))
        val intent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("catwidget://open?screen=${action.uriValue}"),
        )
        setOnClickPendingIntent(viewId, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val profileName = widgetData.getString("widget_profile_name", null)
        val connectionStatus = widgetData.getString("widget_connection_status", null)
        // Widget'in tanitildigi surumden beri var olan cihazlarda bu iki
        // anahtar hic yazilmamis olabilir - o zaman ilk gundeki sabit
        // davranisla (1. buton sohbet, 2. buton kumanda) ayni sonucu verir.
        val slot1Action = slotActionFor(widgetData.getString("widget_slot1_action", null), "chat")
        val slot2Action = slotActionFor(widgetData.getString("widget_slot2_action", null), "remote")

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cat_widget).apply {
                bindSlotButton(context, R.id.widget_btn_chat, slot1Action)
                bindSlotButton(context, R.id.widget_btn_remote, slot2Action)

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
