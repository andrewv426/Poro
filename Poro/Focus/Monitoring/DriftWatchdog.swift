import Foundation

@MainActor
final class DriftWatchdog {
  private let gracePeriodNanoseconds: UInt64
  private var task: Task<Void, Never>?

  init(gracePeriodSeconds: TimeInterval = 10) {
    gracePeriodNanoseconds = UInt64(gracePeriodSeconds * 1_000_000_000)
  }

  func schedule(action: @escaping @MainActor () -> Void) {
    cancel()

    task = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: gracePeriodNanoseconds)
        guard !Task.isCancelled else {
          return
        }
        action()
      } catch {
        return
      }
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}
