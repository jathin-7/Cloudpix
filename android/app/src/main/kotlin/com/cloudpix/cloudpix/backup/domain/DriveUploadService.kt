package com.cloudpix.cloudpix.backup.domain

import android.content.Context
import android.net.Uri
import com.cloudpix.cloudpix.backup.data.DriveAccountEntity

data class UploadOutcome(
    val driveFileId: String,
    val uploadedBytes: Long
)

interface DriveUploadService {
    suspend fun uploadPhoto(
        context: Context,
        account: DriveAccountEntity,
        contentUri: Uri,
        displayName: String,
        mimeType: String
    ): UploadOutcome
}
