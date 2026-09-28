package com.cloudpix.cloudpix.backup.worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.cloudpix.cloudpix.R
import com.cloudpix.cloudpix.backup.data.BackupQueueDao
import com.cloudpix.cloudpix.backup.data.BackupQueueEntity
import com.cloudpix.cloudpix.backup.data.BackupStatus
import com.cloudpix.cloudpix.backup.data.DriveAccountDao
import com.cloudpix.cloudpix.backup.domain.DriveAccountSelector
import com.cloudpix.cloudpix.backup.domain.DriveUploadService
import com.cloudpix.cloudpix.backup.domain.FileHashing
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class BackupWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val backupQueueDao: BackupQueueDao,
    private val driveAccountDao: DriveAccountDao,
    private val driveAccountSelector: DriveAccountSelector,
    private val driveUploadService: DriveUploadService
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        enqueueRecentMediaBackfill()

        val pending = backupQueueDao.getByStatus(BackupStatus.PENDING, MAX_BATCH)
        if (pending.isEmpty()) return Result.success()

        createNotificationChannel()
        setForeground(progressInfo(0, pending.size, "Preparing backup queue"))

        pending.forEachIndexed { index, item ->
            val progressText = "Uploading ${index + 1}/${pending.size}"
            setForeground(progressInfo(index + 1, pending.size, progressText))

            val now = System.currentTimeMillis()
            val uploading = item.copy(status = BackupStatus.UPLOADING, updatedAtEpochMs = now)
            backupQueueDao.update(uploading)

            val result = uploadOne(uploading)
            backupQueueDao.update(result)
        }

        // Continue draining in the background until queue is empty.
        val remaining = backupQueueDao.countByStatus(BackupStatus.PENDING)
        if (remaining > 0) {
            enqueueImmediateDrain()
        }

        return Result.success()
    }

    private suspend fun enqueueRecentMediaBackfill() {
        val resolver = applicationContext.contentResolver
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.SIZE
        )

        val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE}=? OR ${MediaStore.Files.FileColumns.MEDIA_TYPE}=?"
        val args = arrayOf(
            MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
            MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString()
        )

        resolver.query(
            MediaStore.Files.getContentUri("external"),
            projection,
            selection,
            args,
            "${MediaStore.Files.FileColumns.DATE_ADDED} DESC LIMIT $BACKFILL_LIMIT"
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val mediaTypeIdx = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE)
            val nameIdx = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
            val mimeIdx = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
            val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIdx)
                val mediaType = cursor.getInt(mediaTypeIdx)
                val contentUri = when (mediaType) {
                    MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO ->
                        ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)

                    else -> ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
                }

                val displayName = cursor.getString(nameIdx)
                val mimeType = cursor.getString(mimeIdx)
                val size = cursor.getLong(sizeIdx)

                backupQueueDao.insertIgnore(
                    BackupQueueEntity(
                        contentUri = contentUri.toString(),
                        displayName = displayName,
                        mimeType = mimeType,
                        sizeBytes = size,
                        status = BackupStatus.PENDING,
                        createdAtEpochMs = System.currentTimeMillis(),
                        updatedAtEpochMs = System.currentTimeMillis()
                    )
                )
            }
        }
    }

    private fun enqueueImmediateDrain() {
        val request = OneTimeWorkRequestBuilder<BackupWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .setRequiresBatteryNotLow(true)
                    .build()
            )
            .build()

        WorkManager.getInstance(applicationContext)
            .enqueueUniqueWork(DRAIN_WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    private suspend fun uploadOne(item: BackupQueueEntity): BackupQueueEntity {
        val now = System.currentTimeMillis()
        val uri = Uri.parse(item.contentUri)

        val sha256 = FileHashing.sha256(applicationContext.contentResolver, uri)
            ?: return item.copy(
                status = BackupStatus.FAILED,
                errorMessage = "Unable to read file for hashing",
                updatedAtEpochMs = now
            )

        if (backupQueueDao.hasUploadedHash(sha256)) {
            return item.copy(
                sha256 = sha256,
                status = BackupStatus.UPLOADED,
                driveFileId = "duplicate:$sha256",
                errorMessage = null,
                updatedAtEpochMs = now
            )
        }

        val requiredBytes = if (item.sizeBytes > 0) item.sizeBytes else MIN_SIZE_FALLBACK
        val account = driveAccountSelector.pickAccount(requiredBytes)
            ?: return item.copy(
                sha256 = sha256,
                status = BackupStatus.FAILED,
                errorMessage = "No active Google account with enough free storage",
                updatedAtEpochMs = now
            )

        return try {
            val upload = driveUploadService.uploadPhoto(
                context = applicationContext,
                account = account,
                contentUri = uri,
                displayName = item.displayName ?: "IMG_${System.currentTimeMillis()}.jpg",
                mimeType = item.mimeType ?: "image/jpeg"
            )

            driveAccountDao.incrementUsedBytes(
                accountId = account.id,
                deltaBytes = upload.uploadedBytes,
                updatedAt = System.currentTimeMillis()
            )

            item.copy(
                sha256 = sha256,
                status = BackupStatus.UPLOADED,
                accountId = account.id,
                driveFileId = upload.driveFileId,
                errorMessage = null,
                updatedAtEpochMs = System.currentTimeMillis()
            )
        } catch (e: Exception) {
            item.copy(
                sha256 = sha256,
                status = BackupStatus.FAILED,
                errorMessage = e.message ?: "Upload failed",
                updatedAtEpochMs = System.currentTimeMillis()
            )
        }
    }

    private fun progressInfo(done: Int, total: Int, text: String): ForegroundInfo {
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Cloudpix backup running")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(total, done, total <= 0)
            .build()

        return ForegroundInfo(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Cloudpix Backup",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Uploads gallery photos to Google Drive in background"
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "cloudpix.backup.worker"
        private const val NOTIFICATION_ID = 22014
        private const val MAX_BATCH = 25
        private const val MIN_SIZE_FALLBACK = 2L * 1024L * 1024L
        private const val BACKFILL_LIMIT = 250
        private const val DRAIN_WORK_NAME = "cloudpix.backup.drain"
    }
}
