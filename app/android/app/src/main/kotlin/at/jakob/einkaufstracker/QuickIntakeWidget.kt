package at.jakob.einkaufstracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Widget auf dem Startbildschirm: "Wasser" traegt ein Glas ein, "Ergaenzung" oeffnet die Seite Schnell eintragen (ADR-041).
 * Beide Knoepfe starten die App, geschrieben wird immer dort: so gibt es nur einen Weg in Datenbank und Outbox, und man sieht das Ergebnis.
 */
class QuickIntakeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.quick_intake_widget)
        views.setOnClickPendingIntent(R.id.quick_water, action(context, "water", 1))
        views.setOnClickPendingIntent(R.id.quick_open, action(context, "open", 2))
        for (id in ids) manager.updateAppWidget(id, views)
    }

    private fun action(context: Context, name: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(MainActivity.QUICK_ACTION)
            .putExtra(MainActivity.QUICK_EXTRA, name)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
