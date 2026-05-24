import SwiftUI

#if canImport(KeyboardShortcuts)
  import KeyboardShortcuts

  struct ToggleShortcutRecorder: View {
    var body: some View {
      KeyboardShortcuts.Recorder(for: .toggleAssistantWindow)
    }
  }
#else
  struct ToggleShortcutRecorder: View {
    var body: some View {
      EmptyView()
    }
  }
#endif
