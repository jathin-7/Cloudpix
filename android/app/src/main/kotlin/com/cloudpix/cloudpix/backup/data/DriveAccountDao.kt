package com.cloudpix.cloudpix.backup.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface DriveAccountDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(accounts: List<DriveAccountEntity>)

    @Query("SELECT * FROM drive_accounts WHERE is_active = 1 ORDER BY priority_order ASC")
    suspend fun getActiveAccounts(): List<DriveAccountEntity>

    @Query("UPDATE drive_accounts SET used_bytes = used_bytes + :deltaBytes, updated_at_epoch_ms = :updatedAt WHERE id = :accountId")
    suspend fun incrementUsedBytes(accountId: String, deltaBytes: Long, updatedAt: Long)

    @Query("DELETE FROM drive_accounts")
    suspend fun clearAll()
}
