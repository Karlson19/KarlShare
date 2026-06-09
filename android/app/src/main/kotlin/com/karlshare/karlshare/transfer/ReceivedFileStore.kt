package com.karlshare.karlshare.transfer

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream

/**
 * Saves an incoming file to a place the user can actually find, and indexes it
 * so it shows up in the phone's Files app and (for media) the Gallery.
 *
 * Routing is by MIME type, guessed from the file extension when the sender only
 * advertised a generic `application/octet-stream`:
 *   image -> Pictures/Karlshare, video -> Movies/Karlshare,
 *   audio -> Music/Karlshare, everything else -> Download/Karlshare.
 *
 * Android 10+ (API 29) writes through MediaStore (IS_PENDING while writing, no
 * storage permission needed). Android 9 and below writes to the matching public
 * directory and triggers a media scan, using the legacy WRITE_EXTERNAL_STORAGE
 * permission (declared with maxSdkVersion=29 in the manifest).
 */
object ReceivedFileStore {

    fun create(context: Context, name: String, mime: String, size: Long): SavedFile {
        val safeName = sanitize(name)
        val effectiveMime = resolveMime(mime, safeName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            createViaMediaStore(context, safeName, effectiveMime, size)
        } else {
            createViaLegacyFile(context, safeName, effectiveMime)
        }
    }

    private fun createViaMediaStore(
        context: Context,
        name: String,
        mime: String,
        size: Long,
    ): SavedFile {
        val resolver = context.contentResolver
        val (collection, relPath) = when {
            mime.startsWith("image/") ->
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI to
                    "${Environment.DIRECTORY_PICTURES}/Karlshare"
            mime.startsWith("video/") ->
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI to
                    "${Environment.DIRECTORY_MOVIES}/Karlshare"
            mime.startsWith("audio/") ->
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI to
                    "${Environment.DIRECTORY_MUSIC}/Karlshare"
            else ->
                MediaStore.Downloads.EXTERNAL_CONTENT_URI to
                    "${Environment.DIRECTORY_DOWNLOADS}/Karlshare"
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            if (mime.isNotBlank()) put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (size > 0) put(MediaStore.MediaColumns.SIZE, size)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relPath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("Could not create $name in $relPath")
        val out = resolver.openOutputStream(uri)
            ?: throw IOException("Could not open $name for writing")
        return SavedFile(
            output = BufferedOutputStream(out),
            location = "$relPath/$name",
            onCommit = {
                val done = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                runCatching { resolver.update(uri, done, null, null) }
            },
            onDiscard = { runCatching { resolver.delete(uri, null, null) } },
        )
    }

    private fun createViaLegacyFile(context: Context, name: String, mime: String): SavedFile {
        val dirName = when {
            mime.startsWith("image/") -> Environment.DIRECTORY_PICTURES
            mime.startsWith("video/") -> Environment.DIRECTORY_MOVIES
            mime.startsWith("audio/") -> Environment.DIRECTORY_MUSIC
            else -> Environment.DIRECTORY_DOWNLOADS
        }
        val base = File(Environment.getExternalStoragePublicDirectory(dirName), "Karlshare")
            .apply { mkdirs() }
        val target = uniqueFile(base, name)
        val out = BufferedOutputStream(FileOutputStream(target))
        return SavedFile(
            output = out,
            location = target.absolutePath,
            onCommit = {
                runCatching {
                    MediaScannerConnection.scanFile(
                        context,
                        arrayOf(target.absolutePath),
                        if (mime.isBlank()) null else arrayOf(mime),
                        null,
                    )
                }
            },
            onDiscard = { runCatching { target.delete() } },
        )
    }

    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val stem = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "")
        var i = 1
        while (candidate.exists()) {
            val next = if (ext.isEmpty()) "$stem ($i)" else "$stem ($i).$ext"
            candidate = File(dir, next)
            i++
        }
        return candidate
    }

    /** Prefer a concrete MIME guessed from the extension over a generic one. */
    private fun resolveMime(mime: String, name: String): String {
        if (mime.isNotBlank() && mime != "application/octet-stream") return mime
        val ext = name.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return mime
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: mime
    }

    private fun sanitize(name: String): String {
        val cleaned = name.replace(Regex("[\\\\/:*?\"<>|\\r\\n]"), "_").trim()
        return cleaned.ifBlank { "karlshare_file" }
    }
}

/** A destination opened for writing, finalised with [commit] or [discard]. */
class SavedFile(
    val output: OutputStream,
    val location: String,
    private val onCommit: () -> Unit,
    private val onDiscard: () -> Unit,
) {
    fun commit() {
        runCatching {
            output.flush()
            output.close()
        }
        onCommit()
    }

    fun discard() {
        runCatching { output.close() }
        onDiscard()
    }
}
