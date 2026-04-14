import Foundation

/// Watches a directory tree for file changes using GCD DispatchSource.
/// Falls back to polling if the directory doesn't exist yet.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var dirHandle: CInt = -1
    private let path: String
    private let onChange: () -> Void
    private var pollTimer: DispatchSourceTimer?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        // Try to open the directory
        dirHandle = open(path, O_EVTONLY)

        if dirHandle == -1 {
            // Directory doesn't exist yet, poll for its creation
            startPolling()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirHandle,
            eventMask: [.write, .extend, .rename, .link],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.onChange()
        }

        source.setCancelHandler { [weak self] in
            if let handle = self?.dirHandle, handle != -1 {
                close(handle)
                self?.dirHandle = -1
            }
        }

        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.cancel()
        pollTimer = nil
        if dirHandle != -1 {
            close(dirHandle)
            dirHandle = -1
        }
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: self.path) {
                self.pollTimer?.cancel()
                self.pollTimer = nil
                self.start() // Retry with proper FS events
            }
        }
        timer.resume()
        self.pollTimer = timer
    }
}
