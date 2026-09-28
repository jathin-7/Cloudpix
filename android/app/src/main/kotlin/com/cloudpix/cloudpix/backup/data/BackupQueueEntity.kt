package com.cloudpix.cloudpix.backup.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "backup_queue",
    indices = [
        Index(value = ["content_uri"], unique = true),
        Index(value = ["sha256"]),
        Index(value = ["status"])
    ]
)
data class BackupQueueEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "content_uri")
    val contentUri: String,
    @ColumnInfo(name = "display_name")
    val displayName: String?,
    @ColumnInfo(name = "mime_type")
    val mimeType: String?,
    @ColumnInfo(name = "size_bytes")
    val sizeBytes: Long,
    @ColumnInfo(name = "sha256")
    val sha256: String? = null,
    @ColumnInfo(name = "status")
    val status: BackupStatus = BackupStatus.PENDING,
    @ColumnInfo(name = "account_id")
    val accountId: String? = null,
    @ColumnInfo(name = "drive_file_id")
    val driveFileId: String? = null,
    @ColumnInfo(name = "error_message")
    val errorMessage: String? = null,
    @ColumnInfo(name = "created_at_epoch_ms")
    val createdAtEpochMs: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "updated_at_epoch_ms")
    val updatedAtEpochMs: Long = System.currentTimeMillis()
)
