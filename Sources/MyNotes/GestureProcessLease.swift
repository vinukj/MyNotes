import Darwin
import Foundation

/// Ensures only one normal MyNotes process owns the machine-wide pointer gesture.
/// Snapshot and test runs use APP_STORE and deliberately do not acquire this lease.
@MainActor
final class GestureProcessLease {
    static let shared = GestureProcessLease()

    private var fileDescriptor: Int32 = -1

    private init() {}

    func acquire() -> Bool {
        guard fileDescriptor == -1 else { return true }

        let directory = URL.applicationSupportDirectory
            .appending(path: "MyNotes", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let lockURL = directory.appending(path: "gesture.lock")
        let descriptor = lockURL.path.withCString {
            open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        fileDescriptor = descriptor
        return true
    }
}
