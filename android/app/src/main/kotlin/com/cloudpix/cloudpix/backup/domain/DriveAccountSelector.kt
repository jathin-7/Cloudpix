package com.cloudpix.cloudpix.backup.domain

import com.cloudpix.cloudpix.backup.data.DriveAccountDao
import com.cloudpix.cloudpix.backup.data.DriveAccountEntity
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DriveAccountSelector @Inject constructor(
    private val driveAccountDao: DriveAccountDao
) {
    suspend fun pickAccount(requiredBytes: Long): DriveAccountEntity? {
        val active = driveAccountDao.getActiveAccounts()
        return active.firstOrNull { it.availableBytes > requiredBytes + MIN_SAFE_FREE_BYTES }
            ?: active.firstOrNull { it.availableBytes > requiredBytes }
    }

    companion object {
        private const val MIN_SAFE_FREE_BYTES = 5L * 1024L * 1024L
    }
}
