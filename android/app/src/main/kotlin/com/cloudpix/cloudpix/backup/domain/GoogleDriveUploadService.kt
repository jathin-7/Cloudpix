package com.cloudpix.cloudpix.backup.domain

import android.content.Context
import android.net.Uri
import com.cloudpix.cloudpix.backup.data.DriveAccountEntity
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GoogleDriveUploadService @Inject constructor() : DriveUploadService {
    private val client = OkHttpClient()

    override suspend fun uploadPhoto(
        context: Context,
        account: DriveAccountEntity,
        contentUri: Uri,
        displayName: String,
        mimeType: String
    ): UploadOutcome {
        val tempFile = File(context.cacheDir, "upload_${System.currentTimeMillis()}")
        context.contentResolver.openInputStream(contentUri)?.use { input ->
            tempFile.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open file stream from MediaStore")

        val metadata = JSONObject().apply {
            put("name", displayName)
            if (!account.rootFolderId.isNullOrBlank()) {
                put("parents", listOf(account.rootFolderId))
            }
        }

        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart(
                "metadata",
                null,
                metadata.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull())
            )
            .addFormDataPart(
                "file",
                displayName,
                tempFile.asRequestBody((mimeType.ifBlank { "image/jpeg" }).toMediaTypeOrNull())
            )
            .build()

        val request = Request.Builder()
            .url("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,size")
            .addHeader("Authorization", "Bearer ${account.accessToken}")
            .post(body)
            .build()

        val response = client.newCall(request).execute()
        val payload = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            tempFile.delete()
            throw IllegalStateException("Drive upload failed (${response.code}): $payload")
        }

        val json = JSONObject(payload)
        val driveFileId = json.optString("id")
        val size = json.optString("size").toLongOrNull() ?: tempFile.length()
        tempFile.delete()

        if (driveFileId.isBlank()) {
            throw IllegalStateException("Drive file id missing in upload response")
        }

        return UploadOutcome(driveFileId = driveFileId, uploadedBytes = size)
    }
}
