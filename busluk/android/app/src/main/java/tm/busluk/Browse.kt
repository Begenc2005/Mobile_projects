package tm.busluk

import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.CheckBox
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.net.URLEncoder

fun qs(m: Map<String, String>) = m.filter { it.value.isNotEmpty() }
    .map { it.key + "=" + URLEncoder.encode(it.value, "UTF-8") }.joinToString("&")

fun newList() = ListView(A).apply {
    divider = null
    setBackgroundColor(C.BG)
    selector = android.graphics.drawable.ColorDrawable(0)
    clipToPadding = false
}

// ---------------- выбор языка ----------------

class LangScreen : Screen() {
    override fun build(): View {
        val v = vbox(32).apply { gravity = Gravity.CENTER; setBackgroundColor(C.G) }
        v.add(tv("📣", 64f).apply { gravity = Gravity.CENTER })
        v.add(tv("Buşluk", 36f, C.W, true).apply { gravity = Gravity.CENTER }, top = 8)
        v.add(tv("Türkmenistanyň bildirişleri\nОбъявления Туркменистана", 15f, C.W).apply { gravity = Gravity.CENTER }, top = 8)
        fun choose(tk: Boolean) {
            Api.prefs.edit().putString("lang", if (tk) "tk" else "ru").apply()
            L.tk = tk
            A.start()
        }
        v.add(btn("Türkmençe", false) { choose(true) }, top = 40)
        v.add(btn("Русский", false) { choose(false) }, top = 12)
        return v
    }
}

// ---------------- вход по номеру и SMS ----------------

class LoginScreen : Screen() {
    private var phone = ""

    override fun build(): View {
        val sc = ScrollView(A).apply { setBackgroundColor(C.BG) }
        val v = vbox(24)
        sc.addView(v)
        v.add(tv("📣 Buşluk", 30f, C.G, true), top = 24)
        v.add(tv(L["welcome"], 15f, C.SUB), top = 8)

        val step1 = vbox()
        val step2 = vbox().apply { visibility = View.GONE }
        v.add(step1, top = 32)
        v.add(step2, top = 32)

        step1.add(tv(L["phone"], 14f, C.SUB))
        val row = hbox()
        row.add(tv("+993", 18f, C.TXT, true), WRAP, end = 8)
        val ph = edit("65 123456", InputType.TYPE_CLASS_PHONE)
        row.add(ph, 0, WRAP, 1f)
        step1.add(row, top = 6)
        val send = btn(L["get_code"]) {}
        step1.add(send, top = 16)

        val sent = tv("", 14f, C.SUB)
        step2.add(sent)
        val code = edit("______", InputType.TYPE_CLASS_NUMBER).apply {
            textSize = 24f; gravity = Gravity.CENTER; letterSpacing = 0.3f
        }
        step2.add(code, top = 8)
        val go = btn(L["login"]) {}
        step2.add(go, top = 16)
        val again = tv(L["resend"], 14f, C.G).apply { setPadding(0, dp(16), 0, dp(4)) }
        step2.add(again)
        step2.add(tv(L["change_phone"], 14f, C.G).apply {
            setPadding(0, dp(12), 0, dp(4))
            setOnClickListener { step2.visibility = View.GONE; step1.visibility = View.VISIBLE }
        })

        fun requestCode() {
            phone = "993" + ph.text.toString().filter { it.isDigit() }.takeLast(8)
            send.isEnabled = false
            Api.go({ Api.call("POST", "/v1/auth/send", JSONObject().put("phone", phone)) }, {
                send.isEnabled = true
                step1.visibility = View.GONE
                step2.visibility = View.VISIBLE
                sent.text = "${L["code_sent"]} +$phone"
                code.setText("")
                code.requestFocus()
            }, { send.isEnabled = true; toast(errText(it)) })
        }
        send.setOnClickListener { requestCode() }
        again.setOnClickListener { requestCode() }

        go.setOnClickListener {
            go.isEnabled = false
            Api.go({ Api.call("POST", "/v1/auth/verify", JSONObject().put("phone", phone).put("code", code.text.toString())) }, { j ->
                Api.token = j.getString("token")
                Api.prefs.edit().putString("me", j.getJSONObject("user").toString()).apply()
                A.tab(0)
            }, { go.isEnabled = true; toast(errText(it)) })
        }
        // 6 цифр введено (или подставлено из SMS) — входим сразу
        code.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) { if (s?.length == 6 && go.isEnabled) go.performClick() }
        })
        return sc
    }
}

// ---------------- строка поиска с подсказками ----------------

class SearchBox(initial: String, val onSearch: (String) -> Unit) {
    val view = vbox().apply { setBackgroundColor(C.G); setPadding(dp(12), dp(2), dp(12), dp(10)) }
    val input = edit("🔍  " + L["search_hint"], InputType.TYPE_CLASS_TEXT).apply {
        setText(initial)
        imeOptions = EditorInfo.IME_ACTION_SEARCH
        isSingleLine = true
        background = round(C.W, 22)
    }
    private val sug = vbox().apply { background = round(C.W, 12); visibility = View.GONE }
    private var seq = 0

    init {
        view.add(input)
        view.add(sug, top = 6)
        input.setOnEditorActionListener { _, _, _ -> submit(); true }
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val q = s.toString().trim()
                val my = ++seq
                if (!input.hasFocus() || q.length < 2) { sug.visibility = View.GONE; return }
                // ждём паузу в наборе — меньше запросов, меньше трафика
                Api.main.postDelayed({ if (my == seq) fetch(q, my) }, 400)
            }
        })
    }

    fun submit() {
        seq++
        sug.visibility = View.GONE
        A.hideKeyboard()
        onSearch(input.text.toString().trim())
    }

    private fun fetch(q: String, my: Int) {
        Api.go({ Api.call("GET", "/v1/suggest?q=" + URLEncoder.encode(q, "UTF-8")) }, { j ->
            if (my != seq) return@go
            sug.removeAllViews()
            val cats = j.optJSONArray("cats")
            for (i in 0 until (cats?.length() ?: 0)) {
                val id = cats!!.getInt(i)
                val c = Meta.cat(id) ?: continue
                sug.add(line("${c.e}  ${Meta.path(id)}") { seq++; sug.visibility = View.GONE; A.push(ResultsScreen(mutableMapOf("g" to "$id"))) })
            }
            val t = j.optJSONArray("t")
            for (i in 0 until (t?.length() ?: 0)) {
                val s = t!!.getString(i)
                sug.add(line("🔍  $s") { input.setText(s); submit() })
            }
            sug.visibility = if (sug.childCount > 0) View.VISIBLE else View.GONE
        }, {})
    }

    private fun line(s: String, f: () -> Unit) = tv(s, 15f, C.TXT, false, 1).apply {
        setPadding(dp(14), dp(11), dp(14), dp(11))
        setOnClickListener { f() }
    }
}

// ---------------- главная ----------------

class HomeScreen : Screen() {
    override val tab = 0
    private lateinit var feed: Feed
    private lateinit var catsBox: LinearLayout
    private lateinit var vipBox: LinearLayout
    private var loaded = false

    override fun build(): View {
        val root = vbox()
        root.add(topBar("Buşluk", false, "⟳" to { refresh() }))
        val list = newList()
        val head = vbox()
        head.add(SearchBox("") { q -> if (q.isNotEmpty()) A.push(ResultsScreen(mutableMapOf("q" to q))) }.view)
        catsBox = vbox()
        head.add(catsBox)
        vipBox = vbox()
        head.add(vipBox)
        head.add(tv(L["fresh"], 16f, C.TXT, true).apply { setPadding(dp(16), dp(12), dp(16), dp(4)) })
        list.addHeaderView(head, null, false)
        feed = Feed(list) { off, ok, err ->
            Api.go({ Api.call("GET", "/v1/ads?o=$off") }, { j ->
                if (off == 0) setVip(jlist(j.optJSONArray("vip")))
                ok(jlist(j.optJSONArray("items")), j.optBoolean("more"))
            }, err)
        }
        root.add(list, MATCH, 0, 1f)
        return root
    }

    override fun resume() {
        if (loaded) return
        loaded = true
        if (Meta.ready) { drawCats(); feed.reset() }
        // справочник обновляется тихо; если его ещё нет — ждём его, потом лента
        Meta.refresh({ drawCats(); if (feed.items.isEmpty() && !feed.busy) feed.reset() }, {
            if (!Meta.ready) { loaded = false; toast(errText(it)) }
        })
    }

    private fun refresh() { feed.reset() }

    private fun setVip(items: List<JSONObject>) {
        vipBox.removeAllViews()
        if (items.isNotEmpty()) vipBox.add(vipStrip(items))
    }

    private fun drawCats() {
        catsBox.removeAllViews()
        catsBox.add(tv(L["cats"], 16f, C.TXT, true).apply { setPadding(dp(16), dp(12), dp(16), dp(6)) })
        val tops = Meta.tops()
        var row: LinearLayout? = null
        tops.forEachIndexed { i, c ->
            if (i % 4 == 0) { row = hbox().apply { setPadding(dp(8), 0, dp(8), 0) }; catsBox.add(row!!) }
            val cell = vbox(4).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setOnClickListener { openCat(c.i) }
            }
            cell.add(tv(c.e, 26f).apply {
                gravity = Gravity.CENTER
                background = round(C.W, 16)
                setPadding(0, dp(10), 0, dp(10))
            })
            cell.add(tv(c.name, 11.5f, C.TXT, false, 2).apply { gravity = Gravity.CENTER }, top = 4)
            row!!.add(cell, 0, WRAP, 1f)
        }
        val rest = tops.size % 4
        if (rest != 0) repeat(4 - rest) { row!!.add(View(A), 0, 1, 1f) }
    }
}

fun openCat(id: Int) {
    if (Meta.children(id).isNotEmpty()) A.push(CatScreen(id)) else A.push(ResultsScreen(mutableMapOf("g" to "$id")))
}

// ---------------- подкатегории ----------------

class CatScreen(private val id: Int) : Screen() {
    override fun build(): View {
        val c = Meta.cat(id)
        val root = vbox()
        root.add(topBar(c?.name ?: ""))
        val sc = ScrollView(A)
        val v = vbox(12)
        sc.addView(v)
        fun row(icon: String, name: String, bold: Boolean, f: () -> Unit) = hbox(14).apply {
            background = round(C.W, 12)
            add(tv(icon, 22f), WRAP, end = 12)
            add(tv(name, 16f, C.TXT, bold), 0, WRAP, 1f)
            add(tv("›", 20f, C.SUB), WRAP)
            setOnClickListener { f() }
        }
        v.add(row("📂", L["all_in"], true) { A.push(ResultsScreen(mutableMapOf("g" to "$id"))) })
        for (ch in Meta.children(id)) v.add(row(ch.e, ch.name, false) { openCat(ch.i) }, top = 8)
        root.add(sc, MATCH, 0, 1f)
        return root
    }
}

// ---------------- результаты поиска ----------------

class ResultsScreen(val p: MutableMap<String, String>) : Screen() {
    private lateinit var feed: Feed
    private lateinit var chips: LinearLayout
    private lateinit var found: LinearLayout
    private lateinit var vipBox: LinearLayout
    private lateinit var search: SearchBox
    private var first = true

    override fun build(): View {
        val root = vbox()
        val g = p["g"]?.toIntOrNull() ?: 0
        root.add(topBar(if (g > 0) Meta.cat(g)?.name ?: "" else L["search_hint"], true, "⚙" to {
            A.push(FilterScreen(p) { reload() })
        }))
        val list = newList()
        val head = vbox()
        search = SearchBox(p["q"] ?: "") { q -> p["q"] = q; reload() }
        head.add(search.view)
        val hs = HorizontalScrollView(A).apply { isHorizontalScrollBarEnabled = false }
        chips = hbox().apply { setPadding(dp(12), dp(10), dp(12), dp(4)) }
        hs.addView(chips)
        head.add(hs)
        found = vbox()
        head.add(found)
        vipBox = vbox()
        head.add(vipBox)
        list.addHeaderView(head, null, false)
        feed = Feed(list) { off, ok, err ->
            Api.go({ Api.call("GET", "/v1/ads?" + qs(p + ("o" to "$off"))) }, { j ->
                if (off == 0) {
                    vipBox.removeAllViews()
                    val v = jlist(j.optJSONArray("vip"))
                    if (v.isNotEmpty()) vipBox.add(vipStrip(v))
                    showFound(j)
                }
                ok(jlist(j.optJSONArray("items")), j.optBoolean("more"))
            }, err)
        }
        root.add(list, MATCH, 0, 1f)
        return root
    }

    override fun resume() {
        if (first) { first = false; reload() }
    }

    fun reload() {
        drawChips()
        feed.reset()
    }

    private fun showFound(j: JSONObject) {
        found.removeAllViews()
        val c = j.optJSONArray("cats") ?: return
        if (c.length() == 0) return
        found.add(tv(L["found"], 13f, C.SUB).apply { setPadding(dp(16), dp(6), dp(16), 0) })
        val hs = HorizontalScrollView(A).apply { isHorizontalScrollBarEnabled = false }
        val row = hbox().apply { setPadding(dp(12), dp(6), dp(12), dp(4)) }
        for (i in 0 until c.length()) {
            val id = c.getInt(i)
            val cat = Meta.cat(id) ?: continue
            row.add(chip("${cat.e} ${cat.name}") { p["g"] = "$id"; reload() }, WRAP, end = 6)
        }
        hs.addView(row)
        found.add(hs)
    }

    private fun drawChips() {
        chips.removeAllViews()
        val g = p["g"]?.toIntOrNull() ?: 0
        // где искать
        val place = p["c"]?.toIntOrNull()?.let { Meta.city(it)?.name }
            ?: p["r"]?.toIntOrNull()?.let { r -> Meta.regions.firstOrNull { it.i == r }?.name } ?: L["all_tm"]
        chips.add(chip("📍 $place", p["c"] != null || p["r"] != null) {
            pickPlace(true) { r, c ->
                p.remove("r"); p.remove("c")
                if (c > 0) p["c"] = "$c" else if (r > 0) p["r"] = "$r"
                reload()
            }
        }, WRAP, end = 6)
        val sorts = listOf("" to L["s_new"], "cheap" to L["s_cheap"], "dear" to L["s_dear"])
        chips.add(chip("↕ " + sorts.first { it.first == (p["s"] ?: "") }.second, p["s"] != null) {
            pick(L["sort"], sorts.map { it.second }) { i ->
                if (i == 0) p.remove("s") else p["s"] = sorts[i].first
                reload()
            }
        }, WRAP, end = 6)
        val nf = listOf("pmin", "pmax", "f", "ph").count { !p[it].isNullOrEmpty() }
        chips.add(chip("⚙ " + L["filters"] + if (nf > 0) " · $nf" else "", nf > 0) {
            A.push(FilterScreen(p) { reload() })
        }, WRAP, end = 6)
        // подкатегории
        if (g > 0) {
            val parent = Meta.cat(g)?.p ?: 0
            val subs = if (Meta.children(g).isNotEmpty()) Meta.children(g) else Meta.children(parent)
            for (s in subs) chips.add(chip(s.name, s.i == g) {
                p["g"] = if (s.i == g && parent > 0) "$parent" else "${s.i}"
                p.remove("f")
                reload()
            }, WRAP, end = 6)
        }
    }
}

/** Выбор места: регион -> город. cb(region, city); 0 = любой. */
fun pickPlace(allowAll: Boolean, cb: (Int, Int) -> Unit) {
    val regs = Meta.regions
    val names = (if (allowAll) listOf(L["all_tm"]) else emptyList()) + regs.map { it.name }
    pick(L["region"], names) { i ->
        val ri = if (allowAll) i - 1 else i
        if (ri < 0) { cb(0, 0); return@pick }
        val r = regs[ri]
        val cs = Meta.cities.filter { it.g == r.i }
        if (cs.size == 1) { cb(r.i, cs[0].i); return@pick }
        val items = (if (allowAll) listOf("${L["any"]} — ${r.name}") else emptyList()) + cs.map { it.name }
        pick(L["city"], items) { k ->
            val ci = if (allowAll) k - 1 else k
            if (ci < 0) cb(r.i, 0) else cb(r.i, cs[ci].i)
        }
    }
}

// ---------------- фильтры ----------------

class FilterScreen(private val p: MutableMap<String, String>, private val onApply: () -> Unit) : Screen() {
    override fun build(): View {
        val root = vbox()
        root.add(topBar(L["filters"]))
        val sc = ScrollView(A)
        val v = vbox(16)
        sc.addView(v)
        root.add(sc, MATCH, 0, 1f)

        v.add(tv(L["price"] + ", TMT", 14f, C.SUB))
        val pr = hbox()
        val pmin = edit(L["from"], InputType.TYPE_CLASS_NUMBER).apply { setText(p["pmin"] ?: "") }
        val pmax = edit(L["to"], InputType.TYPE_CLASS_NUMBER).apply { setText(p["pmax"] ?: "") }
        pr.add(pmin, 0, WRAP, 1f, end = 8)
        pr.add(pmax, 0, WRAP, 1f)
        v.add(pr, top = 6)

        val photo = CheckBox(A).apply { text = L["with_photo"]; textSize = 16f; isChecked = p["ph"] == "1" }
        v.add(photo, top = 12)

        // характеристики категории (марка, год, комнаты…)
        val g = p["g"]?.toIntOrNull() ?: 0
        val cur = (p["f"] ?: "").split(",").filter { ":" in it }.associate { it.substringBefore(":") to it.substringAfter(":") }.toMutableMap()
        val numIn = HashMap<String, Pair<android.widget.EditText, android.widget.EditText>>()
        for (a in Meta.attrsOf(g)) {
            v.add(tv(a.name + if (a.u.isNotEmpty()) ", ${a.u}" else "", 14f, C.SUB), top = 16)
            if (a.y == "s") {
                val b = tv(cur[a.k]?.let { a.optName(it) } ?: L["any"], 16f).apply {
                    background = round(C.W, 10, C.LINE)
                    setPadding(dp(12), dp(12), dp(12), dp(12))
                }
                b.setOnClickListener {
                    pick(a.name, listOf(L["any"]) + a.o.map { it.name }) { i ->
                        if (i == 0) cur.remove(a.k) else cur[a.k] = a.o[i - 1].k
                        b.text = if (i == 0) L["any"] else a.o[i - 1].name
                    }
                }
                v.add(b, top = 6)
            } else {
                val (lo, hi) = (cur[a.k] ?: "-").split("-").let { (it.getOrNull(0) ?: "") to (it.getOrNull(1) ?: "") }
                val r = hbox()
                val e1 = edit(L["from"], InputType.TYPE_CLASS_NUMBER).apply { setText(lo) }
                val e2 = edit(L["to"], InputType.TYPE_CLASS_NUMBER).apply { setText(hi) }
                r.add(e1, 0, WRAP, 1f, end = 8)
                r.add(e2, 0, WRAP, 1f)
                numIn[a.k] = e1 to e2
                v.add(r, top = 6)
            }
        }

        val bar = hbox(12).apply { setBackgroundColor(C.W) }
        bar.add(btn(L["reset"], false) {
            listOf("pmin", "pmax", "f", "ph", "s", "c", "r").forEach { p.remove(it) }
            A.back(); onApply()
        }, 0, WRAP, 1f, end = 8)
        bar.add(btn(L["apply"]) {
            fun put(k: String, s: String) { if (s.isBlank()) p.remove(k) else p[k] = s.trim() }
            put("pmin", pmin.text.toString())
            put("pmax", pmax.text.toString())
            if (photo.isChecked) p["ph"] = "1" else p.remove("ph")
            for ((k, e) in numIn) {
                val lo = e.first.text.toString().trim()
                val hi = e.second.text.toString().trim()
                if (lo.isEmpty() && hi.isEmpty()) cur.remove(k) else cur[k] = "$lo-$hi"
            }
            put("f", cur.map { "${it.key}:${it.value}" }.joinToString(","))
            A.back(); onApply()
        }, 0, WRAP, 1.6f)
        root.add(bar)
        return root
    }
}
