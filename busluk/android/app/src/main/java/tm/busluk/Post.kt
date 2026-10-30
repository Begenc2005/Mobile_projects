package tm.busluk

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.CheckBox
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** Фото в форме: либо уже на сервере (name), либо новое (jpeg ещё не загружен). */
class Slot(var name: String?, val jpeg: ByteArray?, val preview: Bitmap?)

/**
 * Сжатие перед отправкой: 1280 px по длинной стороне, JPEG 75%, с учётом поворота камеры.
 * Фото с телефона 4–8 МБ превращается в ~150–250 КБ — экономия трафика в 20–40 раз.
 */
fun compress(uri: Uri): Slot? {
    val cr = A.contentResolver
    val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, o) }
    if (o.outWidth <= 0) return null
    var s = 1
    while (maxOf(o.outWidth, o.outHeight) / (s * 2) >= 1280) s *= 2
    var b = cr.openInputStream(uri)?.use {
        BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = s })
    } ?: return null
    val rot = try {
        cr.openInputStream(uri)?.use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } ?: 0f
    } catch (_: Exception) { 0f }
    val k = 1280f / maxOf(b.width, b.height)
    if (k < 1f || rot != 0f) {
        val m = Matrix()
        if (k < 1f) m.postScale(k, k)
        if (rot != 0f) m.postRotate(rot)
        b = Bitmap.createBitmap(b, 0, 0, b.width, b.height, m, true)
    }
    val out = ByteArrayOutputStream()
    b.compress(Bitmap.CompressFormat.JPEG, 75, out)
    val pk = 200f / maxOf(b.width, b.height)
    val prev = Bitmap.createScaledBitmap(b, (b.width * pk).toInt().coerceAtLeast(1), (b.height * pk).toInt().coerceAtLeast(1), true)
    return Slot(null, out.toByteArray(), prev)
}

// ---------------- подать / изменить объявление ----------------

class PostScreen(private val editId: Long?) : Screen() {
    override val tab = if (editId == null) 1 else -1
    private var g = 0
    private var city = 0
    private val vals = HashMap<String, Any>()
    private val slots = ArrayList<Slot>()
    private lateinit var catBtn: TextView
    private lateinit var cityBtn: TextView
    private lateinit var title: EditText
    private lateinit var desc: EditText
    private lateinit var priceIn: EditText
    private lateinit var neg: CheckBox
    private lateinit var tel: EditText
    private lateinit var attrsBox: LinearLayout
    private lateinit var photosRow: LinearLayout

    override fun build(): View {
        val root = vbox()
        root.add(topBar(L[if (editId == null) "new_ad" else "edit_ad"], editId != null))
        val sc = ScrollView(A)
        val v = vbox(16)
        sc.addView(v)
        root.add(sc, MATCH, 0, 1f)

        fun label(s: String) = v.add(tv(s, 14f, C.SUB), top = 14)
        fun selector() = tv("", 16f).apply {
            background = round(C.W, 10, C.LINE)
            setPadding(dp(12), dp(13), dp(12), dp(13))
        }

        label(L["choose_cat"])
        catBtn = selector().apply { setOnClickListener { chooseCat() } }
        v.add(catBtn, top = 6)

        label(L["photos"] + " (≤ 8)")
        val hs = HorizontalScrollView(A).apply { isHorizontalScrollBarEnabled = false }
        photosRow = hbox()
        hs.addView(photosRow)
        v.add(hs, top = 6)

        label(L["title"])
        title = edit("Toyota Camry 2015 / 3 otagly jaý…")
        v.add(title, top = 6)

        label(L["desc"])
        desc = edit("", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES).apply {
            minLines = 4; gravity = Gravity.TOP
        }
        v.add(desc, top = 6)

        attrsBox = vbox()
        v.add(attrsBox)

        label(L["price"] + ", TMT")
        priceIn = edit("0", InputType.TYPE_CLASS_NUMBER)
        v.add(priceIn, top = 6)
        neg = CheckBox(A).apply { text = L["neg"]; textSize = 16f }
        v.add(neg, top = 4)

        label(L["city"])
        cityBtn = selector().apply { setOnClickListener { pickPlace(false) { _, c -> city = c; cityBtn.text = Meta.city(c)?.name ?: "" } } }
        v.add(cityBtn, top = 6)

        label(L["contact_phone"])
        val me = try { JSONObject(Api.prefs.getString("me", "{}")!!) } catch (e: Exception) { JSONObject() }
        tel = edit("+993…", InputType.TYPE_CLASS_PHONE).apply { setText(me.optString("phone").let { if (it.isNotEmpty()) "+$it" else "" }) }
        v.add(tel, top = 6)

        v.add(btn(L[if (editId == null) "publish" else "update"]) { submit() }, top = 24)
        v.add(View(A), MATCH, dp(40))

        // город по умолчанию — последний выбранный
        city = Api.prefs.getInt("last_city", 0)
        cityBtn.text = Meta.city(city)?.name ?: L["choose_city"]
        catBtn.text = L["choose_cat"]
        drawPhotos()
        if (editId != null) loadForEdit()
        return root
    }

    private fun chooseCat() {
        val tops = Meta.tops()
        pick(L["choose_cat"], tops.map { "${it.e}  ${it.name}" }) { i ->
            val t = tops[i]
            val ch = Meta.children(t.i)
            if (ch.isEmpty()) setCat(t.i)
            else pick(t.name, ch.map { "${it.e}  ${it.name}" }) { k -> setCat(ch[k].i) }
        }
    }

    private fun setCat(id: Int) {
        if (id != g) vals.clear()
        g = id
        catBtn.text = Meta.path(id)
        drawAttrs()
    }

    private fun drawAttrs() {
        attrsBox.removeAllViews()
        for (a in Meta.attrsOf(g)) {
            attrsBox.add(tv(a.name + if (a.u.isNotEmpty()) ", ${a.u}" else "", 14f, C.SUB), top = 14)
            if (a.y == "s") {
                val b = tv(vals[a.k]?.let { a.optName(it.toString()) } ?: "—", 16f).apply {
                    background = round(C.W, 10, C.LINE)
                    setPadding(dp(12), dp(13), dp(12), dp(13))
                }
                b.setOnClickListener {
                    pick(a.name, listOf("—") + a.o.map { it.name }) { i ->
                        if (i == 0) vals.remove(a.k) else vals[a.k] = a.o[i - 1].k
                        b.text = if (i == 0) "—" else a.o[i - 1].name
                    }
                }
                attrsBox.add(b, top = 6)
            } else {
                val e = edit("", InputType.TYPE_CLASS_NUMBER).apply { setText(vals[a.k]?.toString() ?: "") }
                e.addTextChangedListener(object : android.text.TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, x: Int, y: Int, z: Int) {}
                    override fun onTextChanged(s: CharSequence?, x: Int, y: Int, z: Int) {}
                    override fun afterTextChanged(s: android.text.Editable?) {
                        val n = s.toString().toLongOrNull()
                        if (n == null) vals.remove(a.k) else vals[a.k] = n
                    }
                })
                attrsBox.add(e, top = 6)
            }
        }
    }

    private fun drawPhotos() {
        photosRow.removeAllViews()
        slots.forEachIndexed { i, s ->
            val iv = ImageView(A).apply { scaleType = ImageView.ScaleType.CENTER_CROP; setBackgroundColor(C.LINE) }
            photosRow.add(iv, dp(84), dp(84), end = 8)
            clip(iv, 10)
            if (s.preview != null) iv.setImageBitmap(s.preview) else s.name?.let { Img.load(iv, Api.thumb(it)) }
            iv.setOnClickListener { ask(L["remove_photo"]) { slots.removeAt(i); drawPhotos() } }
        }
        if (slots.size < 8) photosRow.add(tv("📷\n" + L["add_photo"], 12.5f, C.G).apply {
            gravity = Gravity.CENTER
            background = round(C.G2, 10)
            setOnClickListener { pickPhotos() }
        }, dp(84), dp(84))
    }

    private fun pickPhotos() {
        val i = Intent(Intent.ACTION_GET_CONTENT).setType("image/*")
            .addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        @Suppress("DEPRECATION")
        A.startActivityForResult(Intent.createChooser(i, L["add_photo"]), 7)
    }

    override fun result(req: Int, data: Intent?) {
        if (req != 7 || data == null) return
        val uris = ArrayList<Uri>()
        data.clipData?.let { c -> for (k in 0 until c.itemCount) uris.add(c.getItemAt(k).uri) }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        val free = 8 - slots.size
        Api.go({ uris.take(free).mapNotNull { try { compress(it) } catch (e: Throwable) { null } } }, { got ->
            slots.addAll(got)
            drawPhotos()
        })
    }

    private fun loadForEdit() {
        Api.go({ Api.call("GET", "/v1/ads/$editId") }, { j ->
            setCat(j.optInt("g"))
            val a = j.optJSONObject("a") ?: JSONObject()
            for (k in a.keys()) vals[k] = a.get(k)
            drawAttrs()
            city = j.optInt("c")
            cityBtn.text = Meta.city(city)?.name ?: ""
            title.setText(j.optString("t"))
            desc.setText(j.optString("b"))
            priceIn.setText(j.optLong("p").takeIf { it > 0 }?.toString() ?: "")
            neg.isChecked = j.optBoolean("n")
            tel.setText("+" + j.optString("tel"))
            slots.clear()
            j.optJSONArray("ph")?.let { p -> for (k in 0 until p.length()) slots.add(Slot(p.getString(k), null, null)) }
            drawPhotos()
        })
    }

    private fun submit() {
        val t = title.text.toString().trim()
        when {
            g == 0 -> return toast(L["e_cat"])
            city == 0 -> return toast(L["e_city"])
            t.length < 3 -> return toast(L["e_title"])
        }
        Api.prefs.edit().putInt("last_city", city).apply()
        val dlg = AlertDialog.Builder(A).setMessage(L["uploading"]).setCancelable(false).show()
        val body = JSONObject()
            .put("g", g).put("c", city).put("t", t)
            .put("b", desc.text.toString().trim())
            .put("p", priceIn.text.toString().toLongOrNull() ?: 0)
            .put("n", neg.isChecked)
            .put("a", JSONObject(vals as Map<*, *>))
            .put("tel", tel.text.toString())
        Api.go({
            // новые фото загружаются по одному; уже загруженные повторно не отправляются
            for (s in slots) if (s.name == null && s.jpeg != null) {
                s.name = Api.call("POST", "/v1/photo", raw = s.jpeg).getString("f")
            }
            body.put("ph", JSONArray(slots.mapNotNull { it.name }))
            if (editId == null) Api.call("POST", "/v1/ads", body) else Api.call("PUT", "/v1/ads/$editId", body)
        }, {
            dlg.dismiss()
            toast(L[if (editId == null) "published" else "saved"])
            if (editId == null) A.tab(2) else A.back()
        }, { dlg.dismiss(); toast(errText(it)) })
    }
}
