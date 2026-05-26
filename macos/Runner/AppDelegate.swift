import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  private var pendingFilePath: String?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Appelé par macOS quand l'utilisateur double-clique un .adls/.adlb ou
  /// AirDrop arrive sur l'app.
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    handleIncomingFilePath(filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for f in filenames { handleIncomingFilePath(f) }
    sender.reply(toOpenOrPrint: .success)
  }

  /// API moderne (macOS 11+). Appelée à la place de `openFiles:` quand
  /// macOS livre les fichiers sous forme de NSURL (typique pour AirDrop
  /// vers une app sandboxée).
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.isFileURL {
        handleIncomingFilePath(url.path)
      }
    }
  }

  private func handleIncomingFilePath(_ path: String) {
    if let channel = MainFlutterWindow.incomingFileChannel {
      channel.invokeMethod("fileOpened", arguments: ["path": path])
    } else {
      pendingFilePath = path
    }
  }

  func consumePendingFilePath() -> String? {
    let p = pendingFilePath
    pendingFilePath = nil
    return p
  }
}
