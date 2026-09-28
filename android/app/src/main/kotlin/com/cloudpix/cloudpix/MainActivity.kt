package com.cloudpix.cloudpix

import com.cloudpix.cloudpix.backup.data.DriveAccountDao
import com.cloudpix.cloudpix.backup.data.DriveAccountEntity
import com.cloudpix.cloudpix.backup.data.BackupQueueDao
import com.cloudpix.cloudpix.backup.domain.BackupScheduler
import com.cloudpix.cloudpix.backup.media.GalleryObserverManager
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

	lateinit var driveAccountDao: DriveAccountDao

	lateinit var backupQueueDao: BackupQueueDao

	lateinit var backupScheduler: BackupScheduler

	lateinit var galleryObserverManager: GalleryObserverManager

	private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

	private fun ensureInjected() {
		if (::driveAccountDao.isInitialized && ::backupQueueDao.isInitialized && ::backupScheduler.isInitialized && ::galleryObserverManager.isInitialized) {
			return
		}

		val entryPoint = EntryPointAccessors.fromApplication(
			applicationContext,
			MainActivityEntryPoint::class.java,
		)

		driveAccountDao = entryPoint.driveAccountDao()
		backupQueueDao = entryPoint.backupQueueDao()
		backupScheduler = entryPoint.backupScheduler()
		galleryObserverManager = entryPoint.galleryObserverManager()
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		ensureInjected()

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"startAutoBackup" -> {
					val requireCharging = call.argument<Boolean>("requireCharging") ?: false
					galleryObserverManager.start()
					backupScheduler.ensurePeriodic(requireCharging)
					backupScheduler.enqueueImmediate(requireCharging)
					result.success(true)
				}

				"stopAutoBackup" -> {
					galleryObserverManager.stop()
					result.success(true)
				}

				"enqueueNow" -> {
					val requireCharging = call.argument<Boolean>("requireCharging") ?: false
					backupScheduler.enqueueImmediate(requireCharging)
					result.success(true)
				}

				"upsertAccounts" -> {
					val raw = call.argument<List<Map<String, Any?>>>("accounts").orEmpty()
					scope.launch {
						val entities = raw.mapNotNull { map ->
							val id = map["id"] as? String ?: return@mapNotNull null
							val email = map["email"] as? String ?: return@mapNotNull null
							val token = map["accessToken"] as? String ?: return@mapNotNull null
							DriveAccountEntity(
								id = id,
								email = email,
								accessToken = token,
								rootFolderId = map["rootFolderId"] as? String,
								usedBytes = (map["usedBytes"] as? Number)?.toLong() ?: 0L,
								totalBytes = (map["totalBytes"] as? Number)?.toLong() ?: DEFAULT_TOTAL_BYTES,
								isActive = map["isActive"] as? Boolean ?: true,
								priorityOrder = (map["order"] as? Number)?.toInt() ?: 0,
								updatedAtEpochMs = System.currentTimeMillis()
							)
						}
						driveAccountDao.upsert(entities)
					}
					result.success(true)
				}

				"getUploadedItems" -> {
					scope.launch {
						val rows = backupQueueDao.getUploaded(limit = 500)
						val payload = rows.map {
							mapOf(
								"id" to it.id,
								"contentUri" to it.contentUri,
								"displayName" to it.displayName,
								"mimeType" to it.mimeType,
								"sha256" to it.sha256,
								"accountId" to it.accountId,
								"driveFileId" to it.driveFileId,
								"updatedAt" to it.updatedAtEpochMs
							)
						}
						runOnUiThread { result.success(payload) }
					}
				}

				else -> result.notImplemented()
			}
		}
	}

	companion object {
		private const val CHANNEL = "cloudpix/native_backup"
		private const val DEFAULT_TOTAL_BYTES = 15L * 1024L * 1024L * 1024L
	}
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface MainActivityEntryPoint {
	fun driveAccountDao(): DriveAccountDao
	fun backupQueueDao(): BackupQueueDao
	fun backupScheduler(): BackupScheduler
	fun galleryObserverManager(): GalleryObserverManager
}
