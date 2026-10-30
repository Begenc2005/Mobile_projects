package tm.busluk

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject

// ---------------- карточка объявления ----------------

class AdScreen(private val id: Long, private val preview: JSONObject?) : Screen() {
    private lateinit var body: LinearLayout
    private lateinit var bar: LinearLayout
    private lateinit var favBtn: TextView
    private var ad: JSONObject? = null

    override fun build(): View {
        val root = vbox()
        val top = topBar("", true, "♡" to { toggleFav() }, "⤴" to { share() }, "⚠" to { report() })
        favBtn = top.getChildAt(2) as TextView
        if (Fav.has(id)) favBtn.text = "♥"
        root.add(top)
        val sc = ScrollView(A)
        body = vbox()
        sc.addView(body)
        root.add(sc, MATCH, 0, 1f)
        bar = hbox(10).apply { setBackgroundColor(C.W); elevation = dp(6).toFloat(); visibility = View.GONE }
        root.add(bar)
        preview?.let { draw(it, true) }
        load()
        return root
    }

    private fun load() {
        Api.go({ Api.call("GET", "/v1/ads/$id") }, { j -> ad = j; draw(j, false) }, { e ->
            if (preview == null) {
                body.removeAllViews()
                body.add(tv(errText(e), 15f, C.SUB).apply { setPadding(dp(16), dp(30), dp(16), 0); gravity = Gravity.CENTER })
            } else toast(errText(e))
        })
    }

    private fun draw(j: JSONObject, partial: Boolean) {
        body.removeAllViews()
        val photos = j.optJSONArray("ph")?.let { a -> (0 until a.length()).map { a.getString(it) } }
            ?: listOfNotNull(j.optString("f").ifEmpty { null })

        // фото: в ленте — миниатюра, здесь — полное (≈80–150 КБ), только по открытию
        if (photos.isNotEmpty()) {
            val main = ImageView(A).apply { scaleType = ImageView.ScaleType.CENTER_CROP; setBackgroundColor(C.LINE) }
            body.add(main, MATCH, dp(280))
            var cur = 0
            Img.load(main, if (partial) Api.thumb(photos[0]) else Api.full(photos[0]))
            main.setOnClickListener { if (!partial) A.push(PhotoScreen(photos, cur)) }
            if (photos.size > 1 && !partial) {
                val hs = HorizontalScrollView(A).apply { isHorizontalScrollBarEnabled = false }
                val row = hbox().apply { setPadding(dp(12), dp(8), dp(12), 0) }
                photos.forEachIndexed { i, f ->
                    val t = ImageView(A).apply { scaleType = ImageView.ScaleType.CENTER_CROP; setBackgroundColor(C.LINE) }
                    row.add(t, dp(64), dp(64), end = 6)
                    clip(t, 8)
                    Img.load(t, Api.thumb(f))
                    t.setOnClickListener { cur = i; Img.load(main, Api.full(f)) }
                }
                hs.addView(row)
                body.add(hs)
            }
        }

        val v = vbox(16)
        body.add(v)
        if (j.optBoolean("v")) v.add(tv("⭐ VIP", 13f, C.TXT, true).apply {
            background = round(C.GOLD, 8); setPadding(dp(8), dp(3), dp(8), dp(3))
        }, WRAP, end = 0)
        v.add(tv(price(j.optLong("p"), j.optBoolean("n")), 24f, C.TXT, true), top = 6)
        v.add(tv(j.optString("t"), 18f, C.TXT), top = 4)
        val city = Meta.city(j.optInt("c"))?.name ?: ""
        val seen = if (partial) "" else " · 👁 ${j.optInt("seen")}"
        v.add(tv("📍 $city · ${ago(j.optLong("d"))}$seen", 13.5f, C.SUB), top = 6)
        v.add(tv(Meta.path(j.optInt("g")), 13.5f, C.G), top = 4)
        if (partial) return

        // характеристики
        val attrs = j.optJSONObject("a") ?: JSONObject()
        val shown = Meta.attrsOf(j.optInt("g")).filter { attrs.has(it.k) }
        if (shown.isNotEmpty()) {
            val t = vbox(12).apply { background = round(C.W, 12) }
            for (a in shown) {
                val raw = attrs.get(a.k).toString()
                val value = if (a.y == "s") a.optName(raw) else raw + if (a.u.isNotEmpty()) " ${a.u}" else ""
                val r = hbox().apply { setPadding(0, dp(5), 0, dp(5)) }
                r.add(tv(a.name, 14.5f, C.SUB), 0, WRAP, 1f)
                r.add(tv(value, 14.5f, C.TXT, true), 0, WRAP, 1f)
                t.add(r)
            }
            v.add(t, top = 14)
        }
        val desc = j.optString("b")
        if (desc.isNotEmpty()) {
            v.add(tv(L["desc"], 16f, C.TXT, true), top = 16)
            v.add(tv(desc, 15.5f).apply { setTextIsSelectable(true); setLineSpacing(0f, 1.15f) }, top = 6)
        }
        val seller = j.optString("u")
        if (seller.isNotEmpty()) v.add(tv("👤 ${L["seller"]}: $seller", 14.5f, C.SUB), top = 16)
        v.add(tv("№ $id", 12f, C.SUB), top = 8)

        // нижняя панель: позвонить / SMS или «изменить» для своего
        bar.removeAllViews()
        bar.visibility = View.VISIBLE
        if (j.optBoolean("own")) {
            bar.add(btn(L["edit"], false) { A.push(PostScreen(id)) }, 0, WRAP, 1f, end = 8)
            bar.add(btn(L["promote"]) { promote(id) }, 0, WRAP, 1f)
            return
        }
        val tel = j.optString("tel")
        if (tel.isEmpty()) {
            bar.add(tv(L["login_to_see"], 14f, C.SUB).apply { gravity = Gravity.CENTER }, MATCH)
            return
        }
        bar.add(btn("📞 " + L["call"]) {
            A.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:+$tel")))
        }, 0, WRAP, 1.6f, end = 8)
        bar.add(btn(L["sms"], false) {
            try { A.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:+$tel"))) } catch (_: Exception) {}
        }, 0, WRAP, 1f)
    }

    private fun toggleFav() {
        val j = ad ?: preview ?: return
        val short = JSONObject()
        for (k in listOf("i", "t", "p", "n", "c", "g", "d")) if (j.has(k)) short.put(k, j.get(k))
        val f = j.optJSONArray("ph")?.optString(0) ?: j.optString("f")
        if (f.isNotEmpty()) short.put("f", f)
        val on = Fav.toggle(short)
        favBtn.text = if (on) "♥" else "♡"
    }

    private fun share() {
        val j = ad ?: preview ?: return
        val txt = "${j.optString("t")}\n${price(j.optLong("p"), j.optBoolean("n"))}" +
            (j.optString("tel").takeIf { it.isNotEmpty() }?.let { "\n☎ +$it" } ?: "") + "\n— Buşluk"
        A.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, txt), L["share"]))
    }

    private fun report() {
        val keys = listOf("r_fraud", "r_spam", "r_sold", "r_cat")
        pick(L["report"], keys.map { L[it] }) { i ->
            Api.go({ Api.call("POST", "/v1/ads/$id/report", JSONObject().put("reason", keys[i])) }, { toast(L["report_ok"]) })
        }
    }
}

/** Продвижение: выбор услуги -> страница оплаты банка в браузере. */
fun promote(adId: Long) {
    val pr = Meta.prices
    val svcs = listOf("bump", "vip7", "vip30")
    val names = svcs.map { "${L[it]} — ${money(pr.optLong(it))}" }
    android.app.AlertDialog.Builder(A).setTitle(L["promote"])
        .setItems(names.toTypedArray()) { _, i ->
            Api.go({ Api.call("POST", "/v1/pay", JSONObject().put("ad", adId).put("svc", svcs[i])) }, { j ->
                try { A.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(j.getString("url")))) } catch (_: Exception) {}
            })
        }.setNegativeButton(L["cancel"], null).show()
    toast(L["pay_note"])
}

// ---------------- фото на весь экран ----------------

class PhotoScreen(private val photos: List<String>, private var cur: Int) : Screen() {
    override fun build(): View {
        val f = FrameLayout(A).apply { setBackgroundColor(Color.BLACK) }
        val img = ImageView(A).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
        f.addView(img, FrameLayout.LayoutParams(MATCH, MATCH))
        val count = tv("", 15f, C.W).apply { setPadding(dp(16), dp(16), dp(16), dp(16)) }
        f.addView(count, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.END))
        f.addView(tv("✕", 24f, C.W).apply {
            setPadding(dp(18), dp(12), dp(18), dp(12)); setOnClickListener { A.back() }
        }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.START))
        fun show() { Img.load(img, Api.full(photos[cur])); count.text = "${cur + 1} / ${photos.size}" }
        // касание справа — следующее фото, слева — предыдущее; свайп тоже работает
        var downX = 0f
        img.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> downX = e.x
                MotionEvent.ACTION_UP -> {
                    val dx = e.x - downX
                    val nextPh = if (kotlin.math.abs(dx) > dp(40)) dx < 0 else e.x > v.width / 2
                    cur = if (nextPh) (cur + 1) % photos.size else (cur - 1 + photos.size) % photos.size
                    show()
                    v.performClick()
                }
            }
            true
        }
        show()
        return f
    }
}
