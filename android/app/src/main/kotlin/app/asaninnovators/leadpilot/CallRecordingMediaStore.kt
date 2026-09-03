package app.asaninnovators.leadpilot

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import java.io.File

/**
 * Locates the phone dialer's auto-recorded call file via MediaStore instead
 * of raw filesystem access — the Play-policy-compliant way to read an audio
 * file another app wrote into shared storage. Works with just
 * READ_MEDIA_AUDIO (Android 13+) / READ_EXTERNAL_STORAGE (<=32); unlike the
 * raw-path folder scan this replaces, it does NOT need
 * MANAGE_EXTERNAL_STORAGE ("All files access"), which Google Play rejected
 * this app's declaration for.
 */
object CallRecordingMediaStore {

    /**
     * Recent audio files, newest first, optionally restricted to folders
     * matching [relativePathHints] — fragments like "MIUI/sound_recorder/",
     * relative to the storage volume root. Passed in from the Dart side
     * (CallRecordingService's existing candidate-folder list) rather than
     * duplicated here, so the two can't independently drift.
     *
     * Hints only apply on API 29+ (MediaStore.RELATIVE_PATH was added in
     * Android 10); below that, this returns the newest audio files
     * unfiltered by folder — that device population is now negligible and
     * DATA-based path filtering pre-scoped-storage isn't reliable enough to
     * bother with.
     */
    fun queryRecentAudio(
        context: Context,
        relativePathHints: List<String>,
        limit: Int,
    ): List<Map<String, Any?>> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val useRelativePath =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && relativePathHints.isNotEmpty()

        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.SIZE,
        )
        if (useRelativePath) projection.add(MediaStore.Audio.Media.RELATIVE_PATH)

        val selection: String?
        val selectionArgs: Array<String>?
        if (useRelativePath) {
            selection = relativePathHints.joinToString(" OR ") {
                "${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?"
            }
            selectionArgs = relativePathHints.map { "$it%" }.toTypedArray()
        } else {
            selection = null
            selectionArgs = null
        }

        val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC LIMIT $limit"

        val results = mutableListOf<Map<String, Any?>>()
        try {
            context.contentResolver.query(
                collection,
                projection.toTypedArray(),
                selection,
                selectionArgs,
                sortOrder,
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val pathCol = if (useRelativePath) {
                    cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
                } else {
                    -1
                }
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val contentUri = ContentUris.withAppendedId(collection, id)
                    results.add(
                        mapOf(
                            "contentUri" to contentUri.toString(),
                            "displayName" to (cursor.getString(nameCol) ?: ""),
                            // DATE_MODIFIED is Unix epoch SECONDS; the Dart side
                            // (and CallRecording.recordedAt) expects millis.
                            "dateModifiedMs" to cursor.getLong(dateCol) * 1000L,
                            "sizeBytes" to cursor.getLong(sizeCol),
                            "relativePath" to (if (pathCol >= 0) cursor.getString(pathCol) else null),
                        )
                    )
                }
            }
        } catch (_: Exception) {
            // A malformed selection on some OEM MediaProvider fork, or a
            // transient ContentResolver failure — an empty result is the
            // safe degradation (the caller treats it as "nothing found",
            // same as an empty/unreadable folder used to report).
        }
        return results
    }

    /**
     * Copies a MediaStore-referenced file into the app's own cache dir so it
     * can be read/uploaded like any other local file — ContentResolver is the
     * only way to read another app's shared-storage content without
     * MANAGE_EXTERNAL_STORAGE, and it never hands back a raw filesystem path
     * we can rely on. Called lazily, only for the one recording actually
     * being uploaded, not for every candidate in a list.
     *
     * Returns null on any failure (file vanished, permission revoked
     * mid-copy, etc) rather than throwing — the caller treats this the same
     * as "recording not found".
     */
    fun materializeToCache(context: Context, contentUriString: String): String? {
        return try {
            val uri = Uri.parse(contentUriString)
            val outFile = File(
                context.cacheDir,
                "recording_${System.currentTimeMillis()}_${sanitizedFileName(uri)}",
            )
            val copied = context.contentResolver.openInputStream(uri)?.use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
                true
            } ?: false
            if (!copied) return null
            outFile.absolutePath
        } catch (e: Exception) {
            // Not logging contentUriString: a SAF document URI embeds the
            // full path/filename, which (per RecordingDiagnostics' own
            // privacy contract) may carry a contact's name and phone number.
            Log.w("CallRecordingMediaStore", "materializeToCache failed: $e")
            null
        }
    }

    /**
     * `Uri.lastPathSegment` is only ever a bare filename for a MediaStore
     * content URI (its last segment is a numeric row id). For a
     * DocumentsContract tree/document URI — as produced by
     * [RecordingsFolderAccess] — the "document ID" IS the full path (e.g.
     * `primary:MIUI/sound_recorder/call_rec/Some Name.mp3`), so
     * `lastPathSegment` returns that whole thing, slashes included. Using it
     * directly as a filename silently created non-existent subdirectories in
     * the cache path, so every SAF-sourced materialize failed with a
     * swallowed FileNotFoundException. Taking only the actual last component
     * and stripping characters that are unsafe in a filename (OEM dialers
     * routinely embed emoji/contact-name punctuation) fixes both URI kinds
     * uniformly.
     */
    private fun sanitizedFileName(uri: Uri): String {
        val raw = uri.lastPathSegment ?: "recording"
        val base = raw.substringAfterLast('/')
        return base.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }
}
