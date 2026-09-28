package com.cloudpix.cloudpix.backup.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "drive_accounts")
data class DriveAccountEntity(
    @PrimaryKey
    val id: String,
    @ColumnInfo(name = "email")
    val email: String,
    @ColumnInfo(name = "access_token")
    val accessToken: String,
    @ColumnInfo(name = "root_folder_id")
    val rootFolderId: String?,
    @ColumnInfo(name = "used_bytes")
    val usedBytes: Long,
    @ColumnInfo(name = "total_bytes")
    val totalBytes: Long,
    @ColumnInfo(name = "is_active")
    val isActive: Boolean = true,
    @ColumnInfo(name = "priority_order")
    val priorityOrder: Int = 0,
    @ColumnInfo(name = "updated_at_epoch_ms")
    val updatedAtEpochMs: Long = System.currentTimeMillis()
) {
    val availableBytes: Long
        get() = totalBytes - usedBytes
}
