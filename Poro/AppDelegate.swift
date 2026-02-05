import AppKit
//Object getting lifecycle callbacks from macOS
//Allows us to respond to OS level events such as app launching, closing ,etc
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The assistant window controller will be created here in the next step.
    }
}
