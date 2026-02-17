import Foundation

@MainActor
final class SteadyProgressTimer {
    private var task: Task<Void, Never>?

    func start(interval: Duration = .milliseconds(500), tick: @escaping @MainActor () -> Void) {
        stop()
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}