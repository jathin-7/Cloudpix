package com.cloudpix.cloudpix

import androidx.work.Configuration
import androidx.hilt.work.HiltWorkerFactory
import com.cloudpix.cloudpix.backup.domain.BackupScheduler
import com.cloudpix.cloudpix.backup.media.GalleryObserverManager
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class CloudpixApplication : android.app.Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    @Inject
    lateinit var galleryObserverManager: GalleryObserverManager

    @Inject
    lateinit var backupScheduler: BackupScheduler

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        galleryObserverManager.start()
        backupScheduler.ensurePeriodic(requireCharging = false)
    }
}
