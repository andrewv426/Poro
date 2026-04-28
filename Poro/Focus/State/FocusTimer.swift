import Foundation

/// A dedicated timer for managing the countdown of a focus session.
@MainActor
final class FocusTimer {
  private var timer: Timer?
  private(set) var remainingSeconds: Int = 0
  
  /// Callback invoked every second as the timer ticks.
  var onTick: ((Int) -> Void)?
  
  /// Callback invoked when the timer reaching zero.
  var onComplete: (() -> Void)?

  /// Starts a countdown for the specified duration.
  /// - Parameter minutes: The duration of the session in minutes.
  func start(minutes: Int) {
    stop()
    remainingSeconds = minutes * 60
    
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.tick()
      }
    }
  }

  /// Stops the countdown and invalidates the underlying timer.
  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Manually decrements the remaining time.
  private func tick() {
    guard remainingSeconds > 0 else {
      stop()
      onComplete?()
      return
    }

    remainingSeconds -= 1
    onTick?(remainingSeconds)

    if remainingSeconds == 0 {
      stop()
      onComplete?()
    }
  }

  /// Formats the remaining time into a human-readable string (e.g., "1h 20m" or "45m").
  var remainingTimeText: String {
    guard remainingSeconds > 0 else {
      return "0m"
    }

    let hours = remainingSeconds / 3600
    let minutes = (remainingSeconds % 3600) / 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }

    return "\(max(1, minutes))m"
  }
}
