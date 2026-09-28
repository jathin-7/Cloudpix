package com.cloudpix.cloudpix.backup.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update

@Dao
interface BackupQueueDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIgnore(item: BackupQueueEntity): Long

    @Update
    suspend fun update(item: BackupQueueEntity)

    @Query("SELECT * FROM backup_queue WHERE status = :status ORDER BY created_at_epoch_ms ASC LIMIT :limit")
    suspend fun getByStatus(status: BackupStatus, limit: Int): List<BackupQueueEntity>

    @Query("SELECT EXISTS(SELECT 1 FROM backup_queue WHERE sha256 = :sha256 AND status = 'UPLOADED')")
    suspend fun hasUploadedHash(sha256: String): Boolean

    @Query("SELECT * FROM backup_queue WHERE content_uri = :contentUri LIMIT 1")
    suspend fun findByContentUri(contentUri: String): BackupQueueEntity?

    @Query("SELECT COUNT(*) FROM backup_queue WHERE status = :status")
    suspend fun countByStatus(status: BackupStatus): Int

    @Query("SELECT * FROM backup_queue WHERE status = 'UPLOADED' ORDER BY updated_at_epoch_ms DESC LIMIT :limit")
    suspend fun getUploaded(limit: Int): List<BackupQueueEntity>
}
