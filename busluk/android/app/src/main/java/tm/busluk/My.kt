package tm.busluk

import android.view.Gravity
import android.view.View
import android.widget.ScrollView
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ---------------- мои объявления ----------------

class MyScreen : Screen() {
    override val tab = 2
    private lateinit var feed: Feed

    override fun build(): View {
        val root = vbox()
        root.add(topBar(L["my"], false, "＋" to { A.tab(1) }))
        val list = newList().apply { setPadding(0, dp(6), 0, 0) }
        feed = Feed(list) { _, ok, err ->
            Api.go({ Api.call("GET", "/v1/my/ads") }, { j -> ok(jlist(j.optJSONArray("items")), false) }, err)
        }
        feed.emptyText = L["no_ads"]
        feed.extra = { j ->
            val st = L["st" + j.optInt("s")]
            val vip = j.optLong("x").let { x ->
                if (x * 1000 > System.currentTimeMillis())
                    " · ⭐ ${L["vip_till"]} " + SimpleDateFormat("dd.MM", Locale.US).format(Date(x * 1000)) else ""
            }
            "$st · 👁 ${j.optInt("w")}$vip"
        }
        feed.onClick = { actions(it) }
        root.add(list, MATCH, 0, 1f)
        return root
    }

    // при каждом показе (и после возврата из оплаты) — свежий список
    override fun resume() { feed.reset() }

    private fun actions(j: JSONObject) {
        val id = j.optLong("i")
        val st = j.optInt("s")
        val opts = ArrayList<Pair<String, () -> Unit>>()
        opts.add(L["open"] to { A.push(AdScreen(id, j)) })
        if (st != 2) {
            opts.add(L["edit"] to { A.push(PostScreen(id)) })
            opts.add("🚀 " + L["promote"] to { promote(id) })
            if (st == 0) opts.add(L["hide"] to { setState(id, 1) })
            else opts.add(L["unhide"] to { setState(id, 0) })
        }
        opts.add(L["delete"] to {
            ask(L["del_q"]) { Api.go({ Api.call("DELETE", "/v1/ads/$id") }, { feed.reset() }) }
        })
        pick(j.optString("t"), opts.map { it.first }) { opts[it].second() }
    }

    private fun setState(id: Long, st: Int) {
        Api.go({ Api.call("POST", "/v1/ads/$id/state", JSONObject().put("st", st)) }, { feed.reset() })
    }
}

// ---------------- профиль ----------------

class ProfileScreen : Screen() {
    override val tab = 3

    override fun build(): View {
        val root = vbox()
        root.add(topBar(L["profile"], false))
        val sc = ScrollView(A)
        val v = vbox(16)
        sc.addView(v)
        root.add(sc, MATCH, 0, 1f)

        val me = try { JSONObject(Api.prefs.getString("me", "{}")!!) } catch (e: Exception) { JSONObject() }
        v.add(tv("👤", 44f).apply { gravity = Gravity.CENTER })
        v.add(tv("+" + me.optString("phone"), 18f, C.TXT, true).apply { gravity = Gravity.CENTER }, top = 4)

        v.add(tv(L["name"], 14f, C.SUB), top = 20)
        val name = edit("").apply { setText(me.optString("name")) }
        v.add(name, top = 6)
        v.add(btn(L["save"], false) {
            Api.go({ Api.call("PUT", "/v1/me", JSONObject().put("name", name.text.toString().trim())) }, { u ->
                Api.prefs.edit().putString("me", u.toString()).apply()
                toast(L["saved"])
            })
        }, top = 8)

        fun row(icon: String, s: String, f: () -> Unit) = hbox(14).apply {
            background = round(C.W, 12)
            add(tv(icon, 20f), WRAP, end = 12)
            add(tv(s, 16f), 0, WRAP, 1f)
            add(tv("›", 20f, C.SUB), WRAP)
            setOnClickListener { f() }
        }
        v.add(row("♥", L["fav"]) { A.push(FavScreen()) }, top = 24)
        v.add(row("🌐", L["lang"] + ": " + if (L.tk) "Türkmençe" else "Русский") {
            pick(L["lang"], listOf("Türkmençe", "Русский")) { i ->
                L.tk = i == 0
                Api.prefs.edit().putString("lang", if (L.tk) "tk" else "ru").apply()
                A.relaunch()
            }
        }, top = 8)
        v.add(row("🚪", L["logout"]) {
            ask(L["logout_q"]) {
                fun out() {
                    Api.token = null
                    Api.prefs.edit().remove("me").apply()
                    A.start()
                }
                Api.go({ Api.call("POST", "/v1/auth/logout") }, { out() }, { out() })
            }
        }, top = 8)
        v.add(tv("Buşluk 1.0", 12f, C.SUB).apply { gravity = Gravity.CENTER }, top = 24)

        // имя/телефон могли измениться на другом устройстве
        Api.go({ Api.call("GET", "/v1/me") }, { u -> Api.prefs.edit().putString("me", u.toString()).apply() }, {})
        return root
    }
}

// ---------------- избранное (локально) ----------------

class FavScreen : Screen() {
    private lateinit var feed: Feed

    override fun build(): View {
        val root = vbox()
        root.add(topBar(L["fav"]))
        val list = newList().apply { setPadding(0, dp(6), 0, 0) }
        feed = Feed(list) { _, ok, _ -> ok(Fav.list(), false) }
        feed.emptyText = L["fav_empty"]
        root.add(list, MATCH, 0, 1f)
        return root
    }

    override fun resume() { feed.reset() }
}
