package tm.busluk

import android.app.AlertDialog
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.AbsListView
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// Весь интерфейс строится кодом, без XML и без библиотек AndroidX — так APK остаётся крошечным.

lateinit var A: MainActivity

object C {
    val G = 0xFF0A7D4F.toInt()
    val G2 = 0xFFE3F1EA.toInt()
    val GOLD = 0xFFF2B705.toInt()
    val GOLD2 = 0xFFFFF6D6.toInt()
    val BG = 0xFFF3F4F1.toInt()
    val TXT = 0xFF1B1F1C.toInt()
    val SUB = 0xFF6B736E.toInt()
    val LINE = 0xFFE2E5E0.toInt()
    val RED = 0xFFB3261E.toInt()
    val W = Color.WHITE
}

const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT

fun dp(v: Int): Int = (v * A.resources.displayMetrics.density + 0.5f).toInt()

fun round(color: Int, r: Int = 12, stroke: Int = 0) = GradientDrawable().apply {
    setColor(color)
    cornerRadius = dp(r).toFloat()
    if (stroke != 0) setStroke(dp(1), stroke)
}

fun tv(s: CharSequence, size: Float = 15f, color: Int = C.TXT, bold: Boolean = false, lines: Int = 0) =
    TextView(A).apply {
        text = s
        textSize = size
        setTextColor(color)
        if (bold) typeface = Typeface.DEFAULT_BOLD
        if (lines > 0) { maxLines = lines; ellipsize = TextUtils.TruncateAt.END }
    }

fun vbox(pad: Int = 0) = LinearLayout(A).apply {
    orientation = LinearLayout.VERTICAL
    setPadding(dp(pad), dp(pad), dp(pad), dp(pad))
}

fun hbox(pad: Int = 0) = LinearLayout(A).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(pad), dp(pad), dp(pad), dp(pad))
}

fun btn(s: String, primary: Boolean = true, click: () -> Unit) = TextView(A).apply {
    text = s
    textSize = 16f
    gravity = Gravity.CENTER
    typeface = Typeface.DEFAULT_BOLD
    setTextColor(if (primary) C.W else C.G)
    background = round(if (primary) C.G else C.G2, 12)
    setPadding(dp(16), dp(13), dp(16), dp(13))
    setOnClickListener { click() }
}

fun chip(s: String, on: Boolean = false, click: () -> Unit) = TextView(A).apply {
    text = s
    textSize = 14f
    setTextColor(if (on) C.W else C.TXT)
    background = round(if (on) C.G else C.W, 18, if (on) 0 else C.LINE)
    setPadding(dp(12), dp(7), dp(12), dp(7))
    setOnClickListener { click() }
}

fun edit(hint: String, type: Int = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES) =
    EditText(A).apply {
        this.hint = hint
        inputType = type
        textSize = 16f
        setTextColor(C.TXT)
        background = round(C.W, 10, C.LINE)
        setPadding(dp(12), dp(11), dp(12), dp(11))
    }

fun LinearLayout.add(v: View, w: Int = MATCH, h: Int = WRAP, weight: Float = 0f, top: Int = 0, end: Int = 0): View {
    addView(v, LinearLayout.LayoutParams(w, h, weight).apply { topMargin = dp(top); rightMargin = dp(end) })
    return v
}

fun clip(v: View, r: Int) {
    v.outlineProvider = object : ViewOutlineProvider() {
        override fun getOutline(view: View, o: Outline) {
            o.setRoundRect(0, 0, view.width, view.height, dp(r).toFloat())
        }
    }
    v.clipToOutline = true
}

fun toast(s: String) = Toast.makeText(A, s, Toast.LENGTH_SHORT).show()

fun pick(title: String, items: List<String>, cb: (Int) -> Unit) {
    AlertDialog.Builder(A).setTitle(title).setItems(items.toTypedArray()) { _, i -> cb(i) }.show()
}

fun ask(msg: String, cb: () -> Unit) {
    AlertDialog.Builder(A).setMessage(msg).setPositiveButton(L["yes"]) { _, _ -> cb() }
        .setNegativeButton(L["no"], null).show()
}

/** Шапка экрана: ← Заголовок [действия] */
fun topBar(title: String, back: Boolean = true, vararg actions: Pair<String, () -> Unit>): LinearLayout {
    val h = hbox().apply { setBackgroundColor(C.G); setPadding(dp(4), 0, dp(8), 0); minimumHeight = dp(54) }
    if (back) h.add(tv("←", 22f, C.W).apply {
        setPadding(dp(12), dp(8), dp(12), dp(8)); setOnClickListener { A.back() }
    }, WRAP) else h.add(View(A), dp(12), 1)
    h.add(tv(title, 18f, C.W, true, 1), 0, WRAP, 1f)
    for ((label, f) in actions) h.add(tv(label, 20f, C.W).apply {
        setPadding(dp(10), dp(8), dp(10), dp(8)); setOnClickListener { f() }
    }, WRAP)
    return h
}

private val sp = ' '

fun money(p: Long): String {
    val s = p.toString()
    val b = StringBuilder()
    for (i in s.indices) {
        if (i > 0 && (s.length - i) % 3 == 0) b.append(sp)
        b.append(s[i])
    }
    return "$b${sp}TMT"
}

fun price(p: Long, neg: Boolean): String = when {
    p > 0 && neg -> money(p) + " · " + L["neg"]
    p > 0 -> money(p)
    neg -> L["neg"]
    else -> L["no_price"]
}

fun ago(unix: Long): String {
    val d = Date(unix * 1000)
    val c = Calendar.getInstance()
    val now = Calendar.getInstance()
    c.time = d
    val hm = SimpleDateFormat("HH:mm", Locale.US).format(d)
    val days = (now.get(Calendar.YEAR) - c.get(Calendar.YEAR)) * 366 + now.get(Calendar.DAY_OF_YEAR) - c.get(Calendar.DAY_OF_YEAR)
    return when (days) {
        0 -> "${L["today"]} $hm"
        1 -> "${L["yesterday"]} $hm"
        else -> SimpleDateFormat("dd.MM.yyyy", Locale.US).format(d)
    }
}

// ---------------- карточка объявления в списке ----------------

fun itemRow(convert: View?): View {
    if (convert != null) return convert
    val row = hbox(10)
    row.background = round(C.W, 14)
    val img = ImageView(A).apply { scaleType = ImageView.ScaleType.CENTER_CROP; setBackgroundColor(C.LINE); id = 1 }
    row.add(img, dp(96), dp(96), end = 12)
    clip(img, 10)
    val col = vbox()
    col.add(tv("", 15f, C.TXT, false, 2).apply { id = 2 })
    col.add(tv("", 16f, C.TXT, true, 1).apply { id = 3 }, top = 4)
    col.add(tv("", 12.5f, C.SUB, false, 1).apply { id = 4 }, top = 4)
    row.add(col, 0, WRAP, 1f)
    val wrap = LinearLayout(A).apply { setPadding(dp(12), dp(5), dp(12), dp(5)) }
    wrap.add(row)
    return wrap
}

fun bindRow(v: View, it: JSONObject, extra: String? = null) {
    val vip = it.optBoolean("v")
    val row = (v as LinearLayout).getChildAt(0)
    row.background = round(if (vip) C.GOLD2 else C.W, 14, if (vip) C.GOLD else 0)
    val f = it.optString("f")
    Img.load(v.findViewById(1), if (f.isNotEmpty()) Api.thumb(f) else null)
    v.findViewById<TextView>(2).text = (if (vip) "⭐ " else "") + it.optString("t")
    v.findViewById<TextView>(3).text = price(it.optLong("p"), it.optBoolean("n"))
    val city = Meta.city(it.optInt("c"))?.name ?: ""
    v.findViewById<TextView>(4).text = extra ?: "$city · ${ago(it.optLong("d"))}"
}

/** Адаптер ленты: подгрузка страниц по 20 при прокрутке, подвал «загрузка / пусто / ошибка». */
class Feed(
    private val list: ListView,
    val load: (offset: Int, ok: (List<JSONObject>, Boolean) -> Unit, err: (Api.Err) -> Unit) -> Unit,
) : BaseAdapter() {
    val items = ArrayList<JSONObject>()
    var more = true
    var busy = false
    var extra: ((JSONObject) -> String?)? = null
    var emptyText = L["empty"]
    var onClick: (JSONObject) -> Unit = { A.push(AdScreen(it.optLong("i"), it)) }
    private var gen = 0
    private val foot = tv("", 14f, C.SUB).apply {
        gravity = Gravity.CENTER
        setPadding(dp(16), dp(18), dp(16), dp(28))
    }

    init {
        list.addFooterView(foot, null, false)
        list.adapter = this
        list.setOnScrollListener(object : AbsListView.OnScrollListener {
            override fun onScrollStateChanged(v: AbsListView, s: Int) {}
            override fun onScroll(v: AbsListView, first: Int, visible: Int, total: Int) {
                if (more && !busy && items.isNotEmpty() && first + visible >= total - 4) next()
            }
        })
        list.setOnItemClickListener { _, _, pos, _ ->
            val i = pos - list.headerViewsCount
            if (i in items.indices) onClick(items[i])
        }
    }

    fun reset() {
        items.clear()
        more = true
        busy = false
        notifyDataSetChanged()
        next()
    }

    fun next() {
        if (busy || !more) return
        busy = true
        val my = ++gen
        foot.text = L["loading"]
        foot.setOnClickListener(null)
        load(items.size, { got, m ->
            if (my == gen) {
                busy = false
                items.addAll(got)
                more = m
                notifyDataSetChanged()
                foot.text = if (items.isEmpty() && !m) emptyText else ""
            }
        }, { e ->
            if (my == gen) {
                busy = false
                more = false
                foot.text = errText(e) + "\n↻ " + L["retry"]
                foot.setOnClickListener { more = true; next() }
            }
        })
    }

    override fun getCount() = items.size
    override fun getItem(p: Int) = items[p]
    override fun getItemId(p: Int) = items[p].optLong("i")
    override fun getView(p: Int, convert: View?, parent: ViewGroup?): View {
        val v = itemRow(convert)
        bindRow(v, items[p], extra?.invoke(items[p]))
        return v
    }
}

fun jlist(a: org.json.JSONArray?): List<JSONObject> = (0 until (a?.length() ?: 0)).map { a!!.getJSONObject(it) }

/** Горизонтальная полоса VIP-карточек. */
fun vipStrip(items: List<JSONObject>): View {
    val box = vbox()
    box.add(tv("⭐ " + L["vip"], 16f, C.TXT, true).apply { setPadding(dp(16), dp(10), dp(16), dp(4)) })
    val sc = android.widget.HorizontalScrollView(A).apply { isHorizontalScrollBarEnabled = false }
    val row = hbox().apply { setPadding(dp(12), dp(4), dp(12), dp(6)) }
    for (x in items) {
        val card = vbox(8).apply { background = round(C.GOLD2, 14, C.GOLD); setOnClickListener { A.push(AdScreen(x.optLong("i"), x)) } }
        val img = ImageView(A).apply { scaleType = ImageView.ScaleType.CENTER_CROP; setBackgroundColor(C.LINE) }
        card.add(img, dp(140), dp(100))
        clip(img, 10)
        val f = x.optString("f")
        Img.load(img, if (f.isNotEmpty()) Api.thumb(f) else null)
        card.add(tv(x.optString("t"), 13.5f, C.TXT, false, 2), dp(140), top = 6)
        card.add(tv(price(x.optLong("p"), x.optBoolean("n")), 14f, C.TXT, true, 1), dp(140), top = 2)
        row.add(card, WRAP, end = 8)
    }
    sc.addView(row)
    box.add(sc)
    return box
}
