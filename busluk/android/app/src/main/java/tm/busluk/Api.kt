package tm.busluk

import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.widget.ImageView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Сетевой слой: HttpURLConnection + org.json (встроены в Android, 0 КБ к размеру). */
object Api {
    val BASE: String = BuildConfig.BASE
    lateinit var prefs: SharedPreferences
    lateinit var cacheDir: File

    private val pool = Executors.newFixedThreadPool(3)
    val main = Handler(Looper.getMainLooper())

    var token: String?
        get() = prefs.getString("tok", null)
        set(v) { prefs.edit().putString("tok", v).apply() }

    class Err(val code: String, val http: Int) : Exception(code)

    /** Синхронный вызов (только из фонового потока). gzip Android включает и распаковывает сам. */
    fun call(method: String, path: String, body: JSONObject? = null, raw: ByteArray? = null,
             etag: String? = null): JSONObject {
        val c = URL(BASE + path).openConnection() as HttpURLConnection
        try {
            c.requestMethod = method
            c.connectTimeout = 15000
            c.readTimeout = 30000
            c.useCaches = false
            token?.let { c.setRequestProperty("Authorization", "Bearer $it") }
            etag?.let { c.setRequestProperty("If-None-Match", it) }
            if (body != null || raw != null) {
                val bytes = raw ?: body.toString().toByteArray()
                c.doOutput = true
                c.setRequestProperty("Content-Type", if (raw != null) "image/jpeg" else "application/json")
                c.setFixedLengthStreamingMode(bytes.size)
                c.outputStream.use { it.write(bytes) }
            }
            val code = c.responseCode
            if (code == 304) return JSONObject().put("_304", true)
            val stream = if (code >= 400) c.errorStream else c.inputStream
            val s = stream?.bufferedReader()?.use { it.readText() } ?: ""
            val j = try { if (s.isBlank()) JSONObject() else JSONObject(s) } catch (e: Exception) { JSONObject() }
            if (code >= 400) {
                if (code == 401) main.post { A.loggedOut() }
                throw Err(j.optString("e", "net"), code)
            }
            c.getHeaderField("ETag")?.let { j.put("_etag", it) }
            return j
        } finally {
            c.disconnect()
        }
    }

    /** Фон -> результат в UI-потоке. */
    fun <T> go(work: () -> T, done: (T) -> Unit, fail: (Err) -> Unit = { toast(errText(it)) }) {
        pool.execute {
            try {
                val r = work()
                main.post { done(r) }
            } catch (e: Err) {
                main.post { fail(e) }
            } catch (e: Exception) {
                main.post { fail(Err("net", 0)) }
            }
        }
    }

    fun thumb(f: String) = "$BASE/i/${f}_t.jpg"
    fun full(f: String) = "$BASE/i/$f.jpg"
}

fun errText(e: Api.Err): String = L["e_" + e.code].let { if (it.startsWith("e_")) L["net"] else it }

// ---------------- справочники ----------------

class Cat(val i: Int, val p: Int, val r: String, val t: String, val e: String, val a: List<String>) {
    val name get() = L.pick(r, t)
}
class Opt(val k: String, val r: String, val t: String) { val name get() = L.pick(r, t) }
class Attr(val k: String, val r: String, val t: String, val y: String, val u: String, val o: List<Opt>) {
    val name get() = L.pick(r, t)
    fun optName(key: String) = o.firstOrNull { it.k == key }?.name ?: key
}
class Place(val i: Int, val g: Int, val r: String, val t: String) { val name get() = L.pick(r, t) }

/** Категории, города и цены: один запрос, кэш на диске, повторно только при изменении (ETag). */
object Meta {
    var cats = listOf<Cat>()
    var attrs = mapOf<String, Attr>()
    var cities = listOf<Place>()
    var regions = listOf<Place>()
    var prices = JSONObject()
    val ready get() = cats.isNotEmpty()

    private val file get() = File(Api.cacheDir.parentFile, "meta.json")

    fun loadCached() {
        try { if (file.exists()) parse(JSONObject(file.readText())) } catch (_: Exception) {}
    }

    fun refresh(done: () -> Unit, fail: (Api.Err) -> Unit) {
        Api.go({
            val et = if (ready) Api.prefs.getString("meta_etag", null) else null
            val j = Api.call("GET", "/v1/meta", etag = et)
            if (!j.has("_304")) {
                val tag = j.optString("_etag")
                j.remove("_etag")
                file.writeText(j.toString())
                Api.prefs.edit().putString("meta_etag", tag).apply()
                parse(j)
            }
        }, { done() }, fail)
    }

    private fun strs(a: JSONArray?) = (0 until (a?.length() ?: 0)).map { a!!.getString(it) }

    private fun parse(j: JSONObject) {
        val c = j.getJSONArray("cats")
        cats = (0 until c.length()).map { val o = c.getJSONObject(it)
            Cat(o.getInt("i"), o.optInt("p"), o.getString("r"), o.optString("t"), o.optString("e"), strs(o.optJSONArray("a"))) }
        val at = j.getJSONArray("attrs")
        attrs = (0 until at.length()).map { val o = at.getJSONObject(it)
            val op = o.optJSONArray("o")
            Attr(o.getString("k"), o.getString("r"), o.optString("t"), o.getString("y"), o.optString("u"),
                (0 until (op?.length() ?: 0)).map { k -> val x = op!!.getJSONObject(k); Opt(x.getString("k"), x.getString("r"), x.optString("t")) })
        }.associateBy { it.k }
        fun places(a: JSONArray) = (0 until a.length()).map { val o = a.getJSONObject(it)
            Place(o.getInt("i"), o.optInt("g"), o.getString("r"), o.optString("t")) }
        cities = places(j.getJSONArray("cities"))
        regions = places(j.getJSONArray("regions"))
        prices = j.optJSONObject("prices") ?: JSONObject()
    }

    fun cat(id: Int) = cats.firstOrNull { it.i == id }
    fun children(id: Int) = cats.filter { it.p == id }
    fun tops() = cats.filter { it.p == 0 }
    fun city(id: Int) = cities.firstOrNull { it.i == id }
    fun attrsOf(id: Int): List<Attr> {
        val c = cat(id) ?: return emptyList()
        val keys = if (c.a.isEmpty() && c.p != 0) cat(c.p)?.a ?: emptyList() else c.a
        return keys.mapNotNull { attrs[it] }
    }
    fun path(id: Int): String {
        val c = cat(id) ?: return ""
        val p = cat(c.p)
        return if (p != null) "${p.name} › ${c.name}" else c.name
    }
}

// ---------------- картинки ----------------

/** Лёгкий загрузчик: память (LruCache) + диск (HttpResponseCache, ставится в MainActivity). */
object Img {
    private val pool = Executors.newFixedThreadPool(3)
    private val mem = object : LruCache<String, Bitmap>((Runtime.getRuntime().maxMemory() / 8).toInt()) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    fun load(iv: ImageView, url: String?) {
        iv.tag = url
        if (url == null) { iv.setImageDrawable(null); return }
        val m = mem.get(url)
        if (m != null) { iv.setImageBitmap(m); return }
        iv.setImageDrawable(null)
        pool.execute {
            try {
                val c = URL(url).openConnection() as HttpURLConnection
                c.useCaches = true
                c.connectTimeout = 15000
                val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.RGB_565 }
                val b = c.inputStream.use { BitmapFactory.decodeStream(it, null, opts) }
                if (b != null) {
                    mem.put(url, b)
                    Api.main.post { if (iv.tag == url) iv.setImageBitmap(b) }
                }
            } catch (_: Exception) {}
        }
    }
}

// ---------------- избранное (хранится только на телефоне — без трафика) ----------------

object Fav {
    private fun all(): JSONArray = try { JSONArray(Api.prefs.getString("fav", "[]")) } catch (e: Exception) { JSONArray() }
    fun list(): List<JSONObject> = all().let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
    fun has(id: Long) = list().any { it.optLong("i") == id }
    fun toggle(item: JSONObject): Boolean {
        val id = item.optLong("i")
        val l = list().filter { it.optLong("i") != id }.toMutableList()
        val added = l.size == list().size
        if (added) l.add(0, item)
        Api.prefs.edit().putString("fav", JSONArray(l.take(300)).toString()).apply()
        return added
    }
}
