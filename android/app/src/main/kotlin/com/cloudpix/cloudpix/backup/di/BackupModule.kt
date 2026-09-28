package com.cloudpix.cloudpix.backup.di

import android.content.Context
import androidx.room.Room
import com.cloudpix.cloudpix.backup.data.BackupDatabase
import com.cloudpix.cloudpix.backup.data.BackupQueueDao
import com.cloudpix.cloudpix.backup.data.DriveAccountDao
import com.cloudpix.cloudpix.backup.domain.DriveUploadService
import com.cloudpix.cloudpix.backup.domain.GoogleDriveUploadService
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object BackupModule {
    @Provides
    @Singleton
    fun provideBackupDatabase(@ApplicationContext context: Context): BackupDatabase {
        return Room.databaseBuilder(
            context,
            BackupDatabase::class.java,
            "cloudpix_backup.db"
        ).fallbackToDestructiveMigration().build()
    }

    @Provides
    fun provideBackupQueueDao(database: BackupDatabase): BackupQueueDao = database.backupQueueDao()

    @Provides
    fun provideDriveAccountDao(database: BackupDatabase): DriveAccountDao = database.driveAccountDao()

    @Provides
    @Singleton
    fun provideDriveUploadService(impl: GoogleDriveUploadService): DriveUploadService = impl
}
