package com.cloudpix.cloudpix.backup.media

import android.content.ContentUris
import android.content.ContentValues
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.cloudpix.cloudpix.backup.data.BackupQueueDao
import com.cloudpix.cloudpix.backup.data.BackupQueueEntity
import com.cloudpix.cloudpix.backup.data.BackupStatus
import com.cloudpix.cloudpix.backup.domain.BackupScheduler
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GalleryContentObserver @Inject constructor(
    @ApplicationContext
    private val appContext: android.content.Context,
    private val backupQueueDao: BackupQueueDao,
    private val backupScheduler: BackupScheduler
) : ContentObserver(Handler(Looper.getMainLooper())) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        super.onChange(selfChange, uri)
        scope.launch {
            val item = queryLatestImage(uri) ?: return@launch
            backupQueueDao.insertIgnore(item)
            backupScheduler.enqueueImmediate()
        }
    }

    private fun queryLatestImage(changedUri: Uri?): BackupQueueEntity? {
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.SIZE
        )

        val targetUri = changedUri ?: MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val resolver = appContext.contentResolver

        resolver.query(
            targetUri,
            projection,
            null,
            null,
            "${MediaStore.Images.Media.DATE_ADDED} DESC LIMIT 1"
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null

            val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
            val contentUri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
            val displayName = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME))
            val mimeType = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE))
            val size = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE))

            return BackupQueueEntity(
                contentUri = contentUri.toString(),
                displayName = displayName,
                mimeType = mimeType,
                sizeBytes = size,
                status = BackupStatus.PENDING,
                createdAtEpochMs = System.currentTimeMillis(),
                updatedAtEpochMs = System.currentTimeMillis()
            )
        }

        return null
    }
}
