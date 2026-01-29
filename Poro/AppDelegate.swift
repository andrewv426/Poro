import AppKit
//Object getting lifecycle callbacks from macOS
//Allows us to respond to OS level events such as app launching, closing ,etc
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
    }
}
