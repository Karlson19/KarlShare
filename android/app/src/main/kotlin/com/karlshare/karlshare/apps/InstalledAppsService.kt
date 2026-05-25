package com.karlshare.karlshare.apps

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Lists installed user-facing apps so they can be shared as APKs (Section
 * 5.1 #2 "Pick apps"). Filters out system packages and apps without a
 * splittable APK. Exposed via MethodChannel `karlshare/apps`:
 *   - `list` → List<Map<String, Any>> { packageName, label, sourceApkPath, sizeBytes, versionName }
 */
class InstalledAppsService(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "karlshare/apps"
    }

    private val channel = MethodChannel(messenger, METHOD_CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun dispose() {
        scope.cancel()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> scope.launch {
                try {
                    val apps = listUserApps()
                    withContext(Dispatchers.Main) { result.success(apps) }
                } catch (t: Throwable) {
                    withContext(Dispatchers.Main) {
                        result.error("APPS", t.message ?: "failed to list apps", null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun listUserApps(): List<Map<String, Any?>> {
        val pm = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            PackageManager.PackageInfoFlags.of(0L)
        } else null

        val packages = if (flags != null) {
            pm.getInstalledPackages(flags)
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(0)
        }

        return packages
            .asSequence()
            .filter { pkg ->
                val app = pkg.applicationInfo ?: return@filter false
                // Exclude system apps that the user didn't update — they
                // can't legally be re-shared and most aren't user-facing.
                val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val isUpdatedSystem =
                    (app.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                !isSystem || isUpdatedSystem
            }
            .mapNotNull { pkg ->
                val app = pkg.applicationInfo ?: return@mapNotNull null
                val apk = app.sourceDir ?: return@mapNotNull null
                val apkFile = File(apk)
                if (!apkFile.exists() || !apkFile.canRead()) return@mapNotNull null
                mapOf(
                    "packageName" to pkg.packageName,
                    "label" to pm.getApplicationLabel(app).toString(),
                    "sourceApkPath" to apk,
                    "sizeBytes" to apkFile.length(),
                    "versionName" to (pkg.versionName ?: ""),
                    "iconPng" to iconBase64(app, pm),
                )
            }
            .sortedBy { (it["label"] as? String)?.lowercase() }
            .toList()
    }

    /** Renders the app's launcher icon to a small PNG, base64-encoded for the
     *  Flutter side to show in the grid. Null if anything goes wrong. */
    private fun iconBase64(app: ApplicationInfo, pm: PackageManager): String? = try {
        val bmp = drawableToBitmap(pm.getApplicationIcon(app), 96)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    } catch (_: Throwable) {
        null
    }

    private fun drawableToBitmap(drawable: Drawable, sizePx: Int): Bitmap {
        if (drawable is BitmapDrawable) {
            drawable.bitmap?.let { return Bitmap.createScaledBitmap(it, sizePx, sizePx, true) }
        }
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bmp
    }
}
