package expo.modules.iraqilicencereader

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoIraqiLicenceReaderModule : Module() {

    companion object {
        private const val REQUEST_CODE = 8811
    }

    private var pending: Promise? = null

    private val activity: Activity?
        get() = appContext.activityProvider?.currentActivity

    override fun definition() = ModuleDefinition {
        Name("ExpoIraqiLicenceReader")

        Function("hasCameraPermission") {
            val act = activity ?: return@Function false
            ContextCompat.checkSelfPermission(
                act, Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
        }

        /** يفتح الكاميرا على وجه الإجازة ويرجع JSON نصي */
        AsyncFunction("scanFront") { promise: Promise ->
            launch(LicenceScannerActivity.SIDE_FRONT, promise)
        }

        /** يفتح الكاميرا على ظهر الإجازة (جدول الفئات) ويرجع JSON نصي */
        AsyncFunction("scanBack") { promise: Promise ->
            launch(LicenceScannerActivity.SIDE_BACK, promise)
        }

        OnActivityResult { _, payload ->
            if (payload.requestCode != REQUEST_CODE) return@OnActivityResult
            val promise = pending ?: return@OnActivityResult
            pending = null

            val data = payload.data
            if (payload.resultCode == Activity.RESULT_OK && data != null) {
                val json = data.getStringExtra(LicenceScannerActivity.EXTRA_JSON)
                if (json != null) {
                    promise.resolve(json)
                } else {
                    promise.reject("SCAN_FAILED", "ما رجعت نتيجة من الماسح", null)
                }
                return@OnActivityResult
            }

            val reason = data?.getStringExtra(LicenceScannerActivity.EXTRA_ERROR)
            if (reason == "CAMERA_DENIED") {
                promise.reject("CAMERA_DENIED", "صلاحية الكاميرا مرفوضة", null)
            } else {
                promise.reject("SCAN_CANCELLED", "تم إلغاء المسح", null)
            }
        }
    }

    private fun launch(side: String, promise: Promise) {
        val act = activity
        if (act == null) {
            promise.reject("NO_ACTIVITY", "ما لكيت الواجهة", null)
            return
        }
        if (pending != null) {
            promise.reject("BUSY", "ماسح ثاني شغّال بالفعل", null)
            return
        }

        pending = promise
        val intent = Intent(act, LicenceScannerActivity::class.java)
            .putExtra(LicenceScannerActivity.EXTRA_SIDE, side)
        act.startActivityForResult(intent, REQUEST_CODE)
    }
}
