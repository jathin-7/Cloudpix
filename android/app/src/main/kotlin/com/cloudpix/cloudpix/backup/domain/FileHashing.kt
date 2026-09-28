package com.cloudpix.cloudpix.backup.domain

import android.content.ContentResolver
import android.net.Uri
import java.security.MessageDigest

object FileHashing {
    suspend fun sha256(contentResolver: ContentResolver, uri: Uri): String? {
        return runCatching {
            contentResolver.openInputStream(uri)?.use { input ->
                val digest = MessageDigest.getInstance("SHA-256")
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    digest.update(buffer, 0, read)
                }
                digest.digest().joinToString("") { byte -> "%02x".format(byte) }
            }
        }.getOrNull()
    }
}
