package com.cloudpix.cloudpix.backup.data

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [BackupQueueEntity::class, DriveAccountEntity::class],
    version = 1,
    exportSchema = false
)
abstract class BackupDatabase : RoomDatabase() {
    abstract fun backupQueueDao(): BackupQueueDao
    abstract fun driveAccountDao(): DriveAccountDao
}
