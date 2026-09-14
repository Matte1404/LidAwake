import Foundation
import Darwin

final class SessionLock {
    private let descriptor: Int32
    init(path: String) throws {
        // Keep the inode: unlinking a locked file would allow a second writer.
        descriptor = open(path, O_RDONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o444)
        guard descriptor >= 0 else { throw ControlError.message("Could not open the sleep session lock.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw ControlError.message("Another LidAwake session is running or recovering sleep. Close it and try again.")
        }
    }
    deinit { close(descriptor) }
}

final class FileRecoveryJournal: RecoveryJournal {
    private let descriptor: Int32
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              directoryInfo.st_mode & S_IFMT == S_IFDIR, directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o077 == 0 else {
            throw ControlError.message("The sleep recovery directory must be private to your account.")
        }
        descriptor = open(directory.appendingPathComponent("restore-sleep").path,
                          O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ControlError.message("Could not open sleep recovery data.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0 else {
            close(descriptor)
            throw ControlError.message("Sleep recovery data has unsafe permissions.")
        }
    }
    deinit { close(descriptor) }
    func load() throws -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw ControlError.message("Cannot read sleep recovery data.") }
        return info.st_size > 0 // Any partial nonempty marker requires recovery.
    }
    func save(_ pending: Bool) throws {
        if pending {
            var marker: UInt8 = 1
            guard pwrite(descriptor, &marker, 1, 0) == 1 else {
                throw ControlError.message("Cannot save sleep recovery data.")
            }
        } else if ftruncate(descriptor, 0) != 0 {
            throw ControlError.message("Cannot clear sleep recovery data.")
        }
        guard fsync(descriptor) == 0 else { throw ControlError.message("Cannot sync sleep recovery data.") }
    }
}
