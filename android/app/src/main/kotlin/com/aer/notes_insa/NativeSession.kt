package com.aer.notes_insa

import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantLock

/**
 * Serializes all access to the Mobinsapi native library, which keeps a single
 * shared CAS session. Without this, an abandoned foreground call (one whose Dart
 * future already timed out) could overlap the next call, or a background worker
 * run could interleave with a foreground call, corrupting the shared session.
 */
internal object NativeSession {
    /**
     * Single worker thread so foreground MethodChannel calls run one at a time
     * in FIFO order. A call that outlives its Dart timeout keeps occupying this
     * thread, and the next call queues behind it instead of overlapping.
     */
    val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "mobinsapi-native").apply { isDaemon = true }
    }

    /**
     * Scheduler operations must not queue behind a slow or hung Mobinsapi call.
     * Keep them serial so rapid settings changes still reach WorkManager in
     * order, while using a separate thread from the native CAS session.
     */
    val utilityExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "background-task-scheduler").apply { isDaemon = true }
    }

    /**
     * Held for the duration of a logical native sequence so the background worker
     * and the foreground executor are mutually exclusive. Fair so a waiting
     * foreground call is not starved by back-to-back worker runs.
     */
    val lock = ReentrantLock(true)
}
