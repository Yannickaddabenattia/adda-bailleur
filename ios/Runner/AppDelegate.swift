import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var methodChannel: FlutterMethodChannel?
  private var pendingFilePath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      pendingFilePath = Self.copyToCache(url: url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    methodChannel = FlutterMethodChannel(
      name: "adda_location/incoming_file",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      if call.method == "consumePending" {
        let p = self.pendingFilePath
        self.pendingFilePath = nil
        result(p)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Appelé par iOS (AppDelegate classique) ou relayé par SceneDelegate.
  override func application(_ app: UIApplication,
                            open url: URL,
                            options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    forwardFile(url)
    return true
  }

  func forwardFile(_ url: URL) {
    guard let localPath = Self.copyToCache(url: url) else { return }
    if let ch = methodChannel {
      ch.invokeMethod("fileOpened", arguments: ["path": localPath])
    } else {
      pendingFilePath = localPath
    }
  }

  /// iOS remet souvent des URL security-scoped (iCloud, Fichiers...). On doit
  /// activer le scope, copier les octets dans notre sandbox, puis relâcher.
  /// On renvoie le chemin local que Dart peut lire librement.
  static func copyToCache(url: URL) -> String? {
    let started = url.startAccessingSecurityScopedResource()
    defer { if started { url.stopAccessingSecurityScopedResource() } }

    do {
      let data = try Data(contentsOf: url)
      let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
      let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("incoming_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
      try data.write(to: tmp, options: .atomic)
      return tmp.path
    } catch {
      NSLog("[AppDelegate] copyToCache failed for \(url): \(error)")
      return nil
    }
  }
}
