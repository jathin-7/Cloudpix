package com.cloudpix.cloudpix.backup.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.cloudpix.cloudpix.backup.data.BackupQueueDao
import com.cloudpix.cloudpix.backup.data.BackupStatus
import com.cloudpix.cloudpix.backup.domain.BackupScheduler
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class BackupViewModel @Inject constructor(
    private val backupQueueDao: BackupQueueDao,
    private val backupScheduler: BackupScheduler
) : ViewModel() {

    private val _pendingCount = MutableStateFlow(0)
    val pendingCount: StateFlow<Int> = _pendingCount

    fun refreshQueueStats() {
        viewModelScope.launch {
            _pendingCount.value = backupQueueDao.countByStatus(BackupStatus.PENDING)
        }
    }

    fun triggerManualBackup(requireCharging: Boolean) {
        backupScheduler.enqueueImmediate(requireCharging)
    }
}
