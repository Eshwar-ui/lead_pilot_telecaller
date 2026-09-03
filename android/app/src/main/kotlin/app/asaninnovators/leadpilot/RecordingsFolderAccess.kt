package app.asaninnovators.leadpilot

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log

/**
 * Reads a user-granted call-recordings folder directly off the filesystem via
 * the Storage Access Framework — the fallback for OEMs whose dialer writes
 * into a `.nomedia`-marked folder, which [CallRecordingMediaStore] can never
 * see: `.nomedia` only opts a tree out of the media scanner, not out of SAF,
 * which reads the real filesystem regardless.
 *
 * The tree URI here comes from a one-time [MainActivity.pickRecordingsFolder]
 * grant with `takePersistableUriPermission` — see that method's doc for why
 * this needs custom `ACTION_OPEN_DOCUMENT_TREE` handling rather than relying
 * on `file_picker`'s directory picker.
 *
 * Queries [DocumentsContract] directly (one cursor query per directory level)
 * rather than `androidx.documentfile.DocumentFile` — `DocumentFile.listFiles()`
 * returns children cheaply, but `.name`/`.length()`/`.lastModified()` on EACH
 * child is its own cross-process call to the DocumentsProvider. For a
 * call-recordings folder with ~90 files that's ~270+ Binder round-trips,
 * which measured 5-30+ SECONDS on-device (Redmi/MIUI) — long enough to trip
 * MIUI's "MIUIScout" app-hang watchdog and blow well past any reasonable
 * retry-ladder budget on the Dart side, so recordings were never actually
 * found in practice despite the grant being valid. A single batched cursor
 * query per directory (mirroring how [CallRecordingMediaStore] already reads
 * MediaStore) reads all of a directory's children in one round-trip.
 */
object RecordingsFolderAccess {
    private val audioExtensions = setOf("mp3", "m4a", "amr", "wav", "aac", "ogg", "3gp", "mp4")

    // Same caps the old raw-filesystem scan used: OEM dialers nest recordings
    // by number/date at most 1-2 levels, and a small cap keeps a pathological
    // folder from stalling the platform-channel thread.
    private const val MAX_SCAN_DEPTH = 2
    private const val MAX_ENTRIES = 4000

    /**
     * Recordings under the granted tree, newest-visited-first is NOT
     * guaranteed (see [MAX_ENTRIES]/[MAX_SCAN_DEPTH]) — the Dart side sorts
     * and filters, same as it does with [CallRecordingMediaStore]'s rows.
     * Row shape matches [CallRecordingMediaStore.queryRecentAudio] exactly
     * (`contentUri`/`displayName`/`dateModifiedMs`/`sizeBytes`) so the two
     * sources can be concatenated and processed identically on the Dart side.
     *
     * Returns an empty list (never throws) if the tree URI is invalid or the
     * grant has been revoked since it was persisted — the caller falls back
     * to whatever MediaStore found, same as an empty folder always has.
     */
    private const val TAG = "RecordingsFolderAccess"

    fun listRecordings(context: Context, treeUriString: String, limit: Int): List<Map<String, Any?>> {
        val treeUri = try {
            Uri.parse(treeUriString)
        } catch (e: Exception) {
            Log.w(TAG, "bad tree URI: $e")
            return emptyList()
        }
        val rootDocId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            Log.w(TAG, "getTreeDocumentId failed: $e")
            return emptyList()
        }

        val results = mutableListOf<Map<String, Any?>>()
        var budget = MAX_ENTRIES
        val queue = ArrayDeque<Pair<String, Int>>() // documentId, depth
        queue.add(rootDocId to 0)

        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )

        while (queue.isNotEmpty() && results.size < limit) {
            val (docId, depth) = queue.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
            try {
                val cursor = context.contentResolver.query(childrenUri, projection, null, null, null)
                if (cursor == null) {
                    Log.w(TAG, "query returned null cursor at depth=$depth")
                    continue
                }
                // No per-file logging here: OEM dialers embed the contact's
                // name and phone number in the filename, and this class (like
                // RecordingDiagnostics) is meant to stay free of call-content
                // and PII in logs/telemetry.
                cursor.use {
                    val idCol = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                    val nameCol = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val modCol = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    val sizeCol = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
                    val mimeCol = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    while (it.moveToNext()) {
                        if (budget-- <= 0) return results
                        val childDocId = it.getString(idCol) ?: continue
                        val mime = it.getString(mimeCol)
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            if (depth < MAX_SCAN_DEPTH) queue.add(childDocId to depth + 1)
                            continue
                        }
                        val name = it.getString(nameCol) ?: continue
                        if (!isAudioFile(name)) continue
                        val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childDocId)
                        results.add(
                            mapOf(
                                "contentUri" to childUri.toString(),
                                "displayName" to name,
                                // COLUMN_LAST_MODIFIED is already epoch millis
                                // (unlike MediaStore's DATE_MODIFIED, which is
                                // seconds) — no conversion needed here.
                                "dateModifiedMs" to it.getLong(modCol),
                                "sizeBytes" to it.getLong(sizeCol),
                                "relativePath" to null,
                            )
                        )
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "query threw at depth=$depth: $e")
                continue // unreadable/vanished subfolder — skip, don't abort the walk
            }
        }
        return results
    }

    private fun isAudioFile(name: String): Boolean {
        val dot = name.lastIndexOf('.')
        if (dot == -1) return false
        return audioExtensions.contains(name.substring(dot + 1).lowercase())
    }
}
