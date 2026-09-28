package com.cloudpix.cloudpix.backup.media

import android.provider.MediaStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GalleryObserverManager @Inject constructor(
    @ApplicationContext
    private val appContext: android.content.Context,
    private val observer: GalleryContentObserver
) {
    @Volatile
    private var registered = false

    fun start() {
        if (registered) return
        appContext.contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            observer
        )
        appContext.contentResolver.registerContentObserver(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            true,
            observer
        )
        registered = true
    }

    fun stop() {
        if (!registered) return
        appContext.contentResolver.unregisterContentObserver(observer)
        registered = false
    }
}
