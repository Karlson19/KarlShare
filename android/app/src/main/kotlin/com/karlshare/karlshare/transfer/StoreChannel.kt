package com.karlshare.karlshare.transfer

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Publishes a file the Dart transfer engine has finished receiving (sitting in
 * the app's private dir) into MediaStore via [ReceivedFileStore], so it shows
 * up in the user's Gallery / Files app under Pictures|Movies|Music|Download
 * /Karlshare with its original name.
 *
 * MethodChannel `karlshare/store`:
 *   - `publish { path, name, mime }` -> String location (e.g.
 *     "Pictures/Karlshare/IMG_2301.jpg"). Deletes the private temp file after
 *     a successful copy.
 */
class StoreChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "karlshare/store"
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
            "publish" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name") ?: "karlshare_file"
                val mime = call.argument<String>("mime") ?: ""
                if (path.isNullOrBlank()) {
                    result.error("ARG", "path required", null)
                    return
                }
                scope.launch {
                    try {
                        val src = File(path)
                        val saved = ReceivedFileStore.create(context, name, mime, src.length())
                        try {
                            src.inputStream().use { it.copyTo(saved.output, 64 * 1024) }
                            saved.commit()
                        } catch (t: Throwable) {
                            saved.discard()
                            throw t
                        }
                        src.delete()
                        withContext(Dispatchers.Main) { result.success(saved.location) }
                    } catch (t: Throwable) {
                        withContext(Dispatchers.Main) {
                            result.error("STORE", t.message ?: "publish failed", null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
