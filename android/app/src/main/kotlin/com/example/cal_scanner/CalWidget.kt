package com.example.cal_scanner

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Today's numbers as pushed from Flutter. Everything is zero if the stored day is not today. */
data class CalSnapshot(
    val calories: Int, val calorieGoal: Int,
    val protein: Int, val proteinGoal: Int,
    val carbs: Int, val carbsGoal: Int,
    val fat: Int, val fatGoal: Int,
    val meals: Int,
)

object CalWidgetStore {
    private const val PREFS = "cal_widget_prefs"

    private fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun saveTheme(ctx: Context, theme: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("theme", theme).apply()
    }

    /** "system" (follow the phone), "light" or "dark". */
    fun theme(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("theme", "system") ?: "system"

    fun save(ctx: Context, a: Map<*, *>) {
        fun num(k: String): Float = (a[k] as? Number)?.toFloat() ?: 0f
        (a["theme"] as? String)?.let { saveTheme(ctx, it) }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("date", today())
            .putFloat("calories", num("calories")).putFloat("calorieGoal", num("calorieGoal"))
            .putFloat("protein", num("protein")).putFloat("proteinGoal", num("proteinGoal"))
            .putFloat("carbs", num("carbs")).putFloat("carbsGoal", num("carbsGoal"))
            .putFloat("fat", num("fat")).putFloat("fatGoal", num("fatGoal"))
            .putInt("meals", (a["meals"] as? Number)?.toInt() ?: 0)
            .apply()
    }

    fun load(ctx: Context): CalSnapshot {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val fresh = p.getString("date", null) == today()
        fun v(k: String, def: Float = 0f) = p.getFloat(k, def).roundToInt()
        return CalSnapshot(
            calories = if (fresh) v("calories") else 0, calorieGoal = max(v("calorieGoal", 2000f), 1),
            protein = if (fresh) v("protein") else 0, proteinGoal = max(v("proteinGoal", 120f), 1),
            carbs = if (fresh) v("carbs") else 0, carbsGoal = max(v("carbsGoal", 250f), 1),
            fat = if (fresh) v("fat") else 0, fatGoal = max(v("fatGoal", 65f), 1),
            meals = if (fresh) p.getInt("meals", 0) else 0,
        )
    }
}

abstract class BaseCalWidget : AppWidgetProvider() {
    abstract val layoutId: Int
    abstract fun bind(ctx: Context, v: RemoteViews, s: CalSnapshot)

    // Text views by colour role, used when the user forces light or dark in the app.
    protected open val primaryIds: List<Int> = emptyList()
    protected open val secondaryIds: List<Int> = emptyList()
    protected open val bodyIds: List<Int> = emptyList()
    protected open val hasButton: Boolean = false

    /** "system" relies on the colour resources (values / values-night). */
    private fun applyForcedTheme(v: RemoteViews, theme: String) {
        if (theme != "light" && theme != "dark") return
        val dark = theme == "dark"
        val primary = if (dark) 0xFFF3F4F6.toInt() else 0xFF111827.toInt()
        val secondary = if (dark) 0xFF9CA3AF.toInt() else 0xFF6B7280.toInt()
        val body = if (dark) 0xFFD1D5DB.toInt() else 0xFF374151.toInt()
        v.setInt(R.id.widget_root, "setBackgroundResource",
            if (dark) R.drawable.widget_bg_dark else R.drawable.widget_bg_light)
        primaryIds.forEach { v.setTextColor(it, primary) }
        secondaryIds.forEach { v.setTextColor(it, secondary) }
        bodyIds.forEach { v.setTextColor(it, body) }
        if (hasButton) {
            v.setInt(R.id.btn_scan, "setBackgroundResource",
                if (dark) R.drawable.widget_button_bg_dark else R.drawable.widget_button_bg_light)
            v.setTextColor(R.id.btn_scan, if (dark) 0xFF111827.toInt() else 0xFFFFFFFF.toInt())
        }
    }

    protected fun pct(value: Int, goal: Int) = min(100, (value * 100f / goal).roundToInt())

    fun build(ctx: Context): RemoteViews {
        val v = RemoteViews(ctx.packageName, layoutId)
        bind(ctx, v, CalWidgetStore.load(ctx))
        applyForcedTheme(v, CalWidgetStore.theme(ctx))
        val open = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        v.setOnClickPendingIntent(R.id.widget_root, open)
        return v
    }

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        ids.forEach { mgr.updateAppWidget(it, build(ctx)) }
    }
}

class CalWidget4x4 : BaseCalWidget() {
    override val layoutId = R.layout.widget_4x4
    override val primaryIds = listOf(R.id.tv_title, R.id.tv_calories)
    override val secondaryIds = listOf(R.id.tv_date, R.id.tv_goal)
    override val bodyIds = listOf(
        R.id.tv_left, R.id.lbl_protein, R.id.lbl_carbs, R.id.lbl_fat,
        R.id.tv_protein, R.id.tv_carbs, R.id.tv_fat,
    )
    override val hasButton = true

    override fun bind(ctx: Context, v: RemoteViews, s: CalSnapshot) {
        val left = s.calorieGoal - s.calories
        v.setTextViewText(R.id.tv_date, SimpleDateFormat("EEE, d MMM", Locale.getDefault()).format(Date()))
        v.setTextViewText(R.id.tv_calories, s.calories.toString())
        v.setTextViewText(R.id.tv_goal, "/ ${s.calorieGoal} kcal")
        v.setProgressBar(R.id.pb_calories, 100, pct(s.calories, s.calorieGoal), false)
        v.setTextViewText(
            R.id.tv_left,
            if (left >= 0) "$left kcal left  •  ${s.meals} meal${if (s.meals == 1) "" else "s"} today"
            else "${-left} kcal over  •  ${s.meals} meal${if (s.meals == 1) "" else "s"} today",
        )
        v.setProgressBar(R.id.pb_protein, 100, pct(s.protein, s.proteinGoal), false)
        v.setTextViewText(R.id.tv_protein, "${s.protein}/${s.proteinGoal}g")
        v.setProgressBar(R.id.pb_carbs, 100, pct(s.carbs, s.carbsGoal), false)
        v.setTextViewText(R.id.tv_carbs, "${s.carbs}/${s.carbsGoal}g")
        v.setProgressBar(R.id.pb_fat, 100, pct(s.fat, s.fatGoal), false)
        v.setTextViewText(R.id.tv_fat, "${s.fat}/${s.fatGoal}g")
    }
}

class CalWidget2x2 : BaseCalWidget() {
    override val layoutId = R.layout.widget_2x2
    override val primaryIds = listOf(R.id.tv_calories)
    override val secondaryIds = listOf(R.id.tv_title, R.id.tv_goal)
    override val bodyIds = listOf(R.id.tv_macros)

    override fun bind(ctx: Context, v: RemoteViews, s: CalSnapshot) {
        v.setTextViewText(R.id.tv_calories, s.calories.toString())
        v.setTextViewText(R.id.tv_goal, "of ${s.calorieGoal} kcal")
        v.setProgressBar(R.id.pb_calories, 100, pct(s.calories, s.calorieGoal), false)
        v.setTextViewText(R.id.tv_macros, "P ${s.protein}g  C ${s.carbs}g  F ${s.fat}g")
    }
}

object CalWidgetUpdater {
    fun updateAll(ctx: Context) {
        val mgr = AppWidgetManager.getInstance(ctx)
        listOf(CalWidget4x4(), CalWidget2x2()).forEach { w ->
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, w.javaClass))
            ids.forEach { mgr.updateAppWidget(it, w.build(ctx)) }
        }
    }
}
