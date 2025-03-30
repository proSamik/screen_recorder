import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    /**
     * The main window controller for the application.
     */
    private var mainWindowController: NSWindowController?

    /**
     * Application launched event handler.
     * Sets up the main window controller and makes it visible.
     */
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Load Main.storyboard
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        
        // Instantiate the window controller
        if let windowController = storyboard.instantiateController(withIdentifier: "MainWindowController") as? NSWindowController {
            mainWindowController = windowController
            windowController.showWindow(nil)
        }
    }

    /**
     * Application will terminate event handler.
     * Performs any necessary cleanup before app termination.
     */
    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up resources, stop recording if in progress
    }

    /**
     * Application should terminate event handler. 
     * Returns whether the application should terminate.
     */
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
} 