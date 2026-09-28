package com.cloudpix.cloudpix.backup.domain

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.cloudpix.cloudpix.backup.worker.BackupWorker
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BackupScheduler @Inject constructor(
    @ApplicationContext private val context: Context
) {
    fun enqueueImmediate(requireCharging: Boolean = false) {
        val request = OneTimeWorkRequestBuilder<BackupWorker>()
            .setConstraints(buildConstraints(requireCharging))
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(IMMEDIATE_WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    fun ensurePeriodic(requireCharging: Boolean = false) {
        val request = PeriodicWorkRequestBuilder<BackupWorker>(15, TimeUnit.MINUTES)
            .setConstraints(buildConstraints(requireCharging))
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }

    private fun buildConstraints(requireCharging: Boolean): Constraints {
        return Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresCharging(requireCharging)
            .setRequiresBatteryNotLow(true)
            .build()
    }

    companion object {
        private const val IMMEDIATE_WORK_NAME = "cloudpix.backup.immediate"
        private const val PERIODIC_WORK_NAME = "cloudpix.backup.periodic"
    }
}
