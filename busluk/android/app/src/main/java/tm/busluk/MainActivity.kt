package tm.busluk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.http.HttpResponseCache
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File

/** Экран приложения. Навигация — простой стек, без фрагментов и библиотек. */
abstract class Screen {
    var root: View? = null
    open val tab = -1          // 0..3 — корневой экран вкладки (показывается нижняя панель)
    abstract fun build(): View
    open fun resume() {}
    open fun result(req: Int, data: Intent?) {}
}

class MainActivity : Activity() {
    private val stack = ArrayList<Screen>()
    private lateinit var host: FrameLayout
    private lateinit var tabs: LinearLayout

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        A = this
        Api.prefs = getSharedPreferences("b", Context.MODE_PRIVATE)
        Api.cacheDir = cacheDir
        // дисковый HTTP-кэш: фото с сервера (immutable) больше не скачиваются повторно
        try { HttpResponseCache.install(File(cacheDir, "http"), 40L shl 20) } catch (_: Exception) {}
        L.tk = Api.prefs.getString("lang", "tk") == "tk"
        Meta.loadCached()

        val root = vbox()
        root.setBackgroundColor(C.BG)
        host = FrameLayout(this)
        root.add(host, MATCH, 0, 1f)
        tabs = hbox().apply { setBackgroundColor(C.W); elevation = dp(8).toFloat() }
        root.add(tabs)
        setContentView(root)
        start()
    }

    fun start() {
        stack.clear()
        buildTabs()
        when {
            !Api.prefs.contains("lang") -> push(LangScreen())
            Api.token == null -> push(LoginScreen())
            else -> push(HomeScreen())
        }
    }

    private fun buildTabs() {
        tabs.removeAllViews()
        val names = listOf("🏠" to "home", "➕" to "post", "📋" to "my", "👤" to "profile")
        names.forEachIndexed { i, (ico, key) ->
            val t = vbox().apply {
                gravity = Gravity.CENTER
                setPadding(0, dp(6), 0, dp(6))
                setOnClickListener { tab(i) }
            }
            t.add(TextView(A).apply { text = ico; textSize = 20f; gravity = Gravity.CENTER })
            t.add(TextView(A).apply { text = L[key]; textSize = 11.5f; gravity = Gravity.CENTER })
            tabs.add(t, 0, WRAP, 1f)
        }
    }

    fun tab(i: Int) {
        stack.clear()
        push(when (i) { 1 -> PostScreen(null); 2 -> MyScreen(); 3 -> ProfileScreen(); else -> HomeScreen() })
    }

    fun push(s: Screen) { stack.add(s); show() }

    fun replace(s: Screen) { if (stack.isNotEmpty()) stack.removeAt(stack.size - 1); push(s) }

    fun back() {
        when {
            stack.size > 1 -> { stack.removeAt(stack.size - 1); show() }
            (stack.lastOrNull()?.tab ?: 0) > 0 -> tab(0)
            else -> finish()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() = back()

    private fun show() {
        val s = stack.last()
        hideKeyboard()
        host.removeAllViews()
        val v = s.root ?: s.build().also { s.root = it }
        (v.parent as? ViewGroup)?.removeView(v)
        host.addView(v)
        tabs.visibility = if (s.tab >= 0) View.VISIBLE else View.GONE
        for (i in 0 until tabs.childCount) {
            val on = i == s.tab
            val t = tabs.getChildAt(i) as LinearLayout
            (t.getChildAt(1) as TextView).setTextColor(if (on) C.G else C.SUB)
            t.alpha = if (on) 1f else 0.75f
        }
        s.resume()
    }

    fun hideKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        currentFocus?.let { imm.hideSoftInputFromWindow(it.windowToken, 0) }
    }

    fun loggedOut() {
        if (Api.token == null && stack.lastOrNull() is LoginScreen) return
        Api.token = null
        stack.clear()
        push(LoginScreen())
    }

    /** Смена языка: пересобрать интерфейс. */
    fun relaunch() {
        stack.clear()
        buildTabs()
        tab(3)
    }

    private var firstResume = true

    override fun onResume() {
        super.onResume()
        if (firstResume) { firstResume = false; return }
        // возврат из браузера после оплаты — экран «Мои» обновится сам
        if (stack.isNotEmpty()) stack.last().resume()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(req: Int, res: Int, data: Intent?) {
        super.onActivityResult(req, res, data)
        if (res == RESULT_OK && stack.isNotEmpty()) stack.last().result(req, data)
    }

    override fun onStop() {
        super.onStop()
        HttpResponseCache.getInstalled()?.flush()
    }
}
