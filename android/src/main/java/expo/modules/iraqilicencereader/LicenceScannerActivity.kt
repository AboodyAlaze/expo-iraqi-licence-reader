package expo.modules.iraqilicencereader

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import expo.modules.iraqilicencereader.parser.LicenceCategory
import expo.modules.iraqilicencereader.parser.LicenceFront
import expo.modules.iraqilicencereader.parser.LicenceJson
import expo.modules.iraqilicencereader.parser.LicenceParser
import expo.modules.iraqilicencereader.parser.TextBlock
import java.util.concurrent.Executors

/**
 * شاشة كاميرا تقرأ وجه أو ظهر إجازة السياقة.
 *
 * الوجه: نطلب اتفاق 3 إطارات على نفس الـ MRZ — رقم التحقق وحده
 * ممكن تصادفه قراءة خاطئة باحتمال 1 من 10.
 *
 * الظهر: نمرّر إحداثيات كل سطر، فنستنتج صف كل زوج تواريخ هندسياً،
 * ونطلب اتفاق إطارين لأن الجدول ما عنده رقم تحقق.
 */
class LicenceScannerActivity : ComponentActivity() {

    companion object {
        const val EXTRA_SIDE = "side"
        const val EXTRA_JSON = "json"
        const val EXTRA_ERROR = "error"
        const val SIDE_FRONT = "front"
        const val SIDE_BACK = "back"

        private const val FRONT_VOTES = 3
        private const val BACK_VOTES = 2
        private const val FALLBACK_AFTER_FRAMES = 40
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    private lateinit var side: String
    private lateinit var previewView: PreviewView
    private lateinit var hintView: TextView
    private lateinit var votesView: TextView
    private lateinit var fallbackButton: Button

    @Volatile private var done = false
    private var frames = 0

    // حالة التصويت — تُلمس فقط من الـ main thread (مستمع ML Kit)
    private val votes = HashMap<String, Int>()
    private val bestFront = HashMap<String, LicenceFront>()
    private var bestViz: LicenceFront? = null

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startCamera() else fail("CAMERA_DENIED")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        side = intent.getStringExtra(EXTRA_SIDE) ?: SIDE_FRONT

        buildUi()

        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) startCamera() else permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    // ---------- الواجهة ----------

    private fun buildUi() {
        val root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)

        previewView = PreviewView(this)
        root.addView(
            previewView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        // الشريط السفلي: التلميح + نصيحة التصوير
        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.argb(166, 0, 0, 0))
            setPadding(dp(16), dp(16), dp(16), dp(24))
        }
        hintView = TextView(this).apply {
            text = if (side == SIDE_FRONT) "وجّه الكاميرا على وجه البطاقة"
                   else "وجّه الكاميرا على جدول الفئات بالظهر"
            setTextColor(Color.WHITE)
            textSize = 15f
            gravity = Gravity.CENTER
        }
        val tips = TextView(this).apply {
            text = "ضوء جيد · بدون ميلان · خلفية فاتحة"
            setTextColor(Color.rgb(189, 189, 189))
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(0, dp(4), 0, 0)
        }
        bottom.addView(hintView)
        bottom.addView(tips)
        root.addView(
            bottom,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        )

        // عدّاد التصويت
        votesView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.MONOSPACE
            setBackgroundColor(Color.argb(204, 27, 94, 32))
            setPadding(dp(20), dp(8), dp(20), dp(8))
            visibility = View.GONE
        }
        root.addView(
            votesView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL
            ).apply { topMargin = dp(64) }
        )

        // إلغاء
        val cancel = Button(this).apply {
            text = "إلغاء"
            setOnClickListener { fail("SCAN_CANCELLED") }
        }
        root.addView(
            cancel,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.END
            ).apply { topMargin = dp(40); marginEnd = dp(16) }
        )

        // مخرج احتياطي للوجه: إذا ما انقرأ الـ MRZ بعد محاولات كثيرة
        fallbackButton = Button(this).apply {
            text = "اكتفِ بقراءة الوجه"
            visibility = View.GONE
            setOnClickListener {
                val v = bestViz
                if (v != null && !done) {
                    done = true
                    finishWith(LicenceJson.front(v))
                }
            }
        }
        root.addView(
            fallbackButton,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).apply { bottomMargin = dp(120) }
        )

        setContentView(root)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    // ---------- الكاميرا ----------

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val provider = future.get()

            val preview = Preview.Builder().build().apply {
                setSurfaceProvider(previewView.surfaceProvider)
            }

            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            analysis.setAnalyzer(executor) { proxy ->
                @Suppress("UnsafeOptInUsageError")
                val media = proxy.image
                if (media == null || done) {
                    proxy.close()
                    return@setAnalyzer
                }

                val image = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
                recognizer.process(image)
                    .addOnSuccessListener { result ->
                        if (done) return@addOnSuccessListener
                        frames++
                        if (side == SIDE_FRONT) handleFront(result.text) else handleBack(result)
                    }
                    .addOnCompleteListener { proxy.close() }
            }

            provider.unbindAll()
            provider.bindToLifecycle(
                this,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                analysis
            )
        }, ContextCompat.getMainExecutor(this))
    }

    // ---------- الوجه ----------

    private fun handleFront(text: String) {
        val parsed = LicenceParser.parseFront(text)
        val mrz = parsed.mrz

        if (mrz == null) {
            val current = bestViz
            if (current == null || parsed.viz.richness > current.viz.richness) bestViz = parsed

            hintView.text = "ابحث عن السطر السفلي للبطاقة"
            votesView.visibility = View.GONE

            if (frames > FALLBACK_AFTER_FRAMES && bestViz != null) {
                fallbackButton.visibility = View.VISIBLE
            }
            return
        }

        val key = mrz.raw
        val count = (votes[key] ?: 0) + 1
        votes[key] = count

        val existing = bestFront[key]
        if (existing == null || parsed.viz.richness > existing.viz.richness) {
            bestFront[key] = parsed
        }

        hintView.text = "ثبّت البطاقة — جاري التأكيد"
        votesView.text = "$count / $FRONT_VOTES"
        votesView.visibility = View.VISIBLE
        fallbackButton.visibility = View.GONE

        if (count >= FRONT_VOTES) {
            done = true
            finishWith(LicenceJson.front(bestFront[key] ?: parsed))
        }
    }

    // ---------- الظهر ----------

    private fun handleBack(result: Text) {
        val found = LicenceParser.parseBack(result.toBlocks(), result.text)

        if (found.isEmpty()) {
            hintView.text = "وجّه الكاميرا على جدول الفئات"
            votesView.visibility = View.GONE
            return
        }

        val key = found.joinToString("|") { "${it.code}:${it.issueDate}:${it.expiryDate}" }
        val count = (votes[key] ?: 0) + 1
        votes[key] = count

        hintView.text = "لقينا: " + found.joinToString("، ") { it.code }
        votesView.text = "$count / $BACK_VOTES"
        votesView.visibility = View.VISIBLE

        if (count >= BACK_VOTES) {
            done = true
            finishWith(LicenceJson.back(found))
        }
    }

    /** يحوّل نتيجة ML Kit لقطع نص مع إحداثياتها الحقيقية */
    private fun Text.toBlocks(): List<TextBlock> {
        val out = ArrayList<TextBlock>()
        for (block in textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox ?: continue
                out.add(TextBlock(line.text, box.left, box.top, box.right, box.bottom))
            }
        }
        return out
    }

    // ---------- الإنهاء ----------

    private fun finishWith(json: String) {
        runOnUiThread {
            setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_JSON, json))
            finish()
        }
    }

    private fun fail(reason: String) {
        done = true
        setResult(Activity.RESULT_CANCELED, Intent().putExtra(EXTRA_ERROR, reason))
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
        recognizer.close()
    }
}
