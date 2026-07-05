import Foundation

/// iOS counterpart of `NativeSession.kt`. Serializes all access to the
/// `MobinsApiClient` native library, which keeps a single shared CAS session.
/// Without this, an abandoned foreground call (one whose Dart future already
/// timed out) could overlap the next call, or the background task could
/// interleave with a foreground call, corrupting the shared session.
enum NativeSession {
    /// Serial queue so foreground MethodChannel calls run one at a time in FIFO
    /// order. A call that outlives its Dart timeout keeps this queue busy and the
    /// next call queues behind it instead of overlapping.
    static let queue = DispatchQueue(label: "com.aer.notes_insa.native")

    /// Held for the duration of a logical native sequence so the background task
    /// and the foreground queue are mutually exclusive on the shared CAS session.
    static let lock = NSLock()
}
