import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
                         UIDocumentPickerDelegate {

  private var methodChannel: FlutterMethodChannel?
  private var folderChannel: FlutterMethodChannel?
  private var pendingFilePath: String?

  /// Callback Flutter en attente pendant l'affichage du sélecteur de dossier.
  private var folderPickerResult: FlutterResult?

  /// URL security-scoped en cours d'accès, par bookmark (pour stopAccess).
  private var scopedFolderURLs: [String: URL] = [:]

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
    let messenger = engineBridge.applicationRegistrar.messenger()

    methodChannel = FlutterMethodChannel(
      name: "adda_location/incoming_file",
      binaryMessenger: messenger
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

    // Sauvegarde auto : dossier externe choisi + security-scoped bookmark,
    // pour écrire durablement sur pCloud / un disque virtuel / un fournisseur
    // Fichiers, en conservant l'accès après relance.
    folderChannel = FlutterMethodChannel(
      name: "adda_location/secure_folder",
      binaryMessenger: messenger
    )
    folderChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleFolderCall(call, result) ?? result(nil)
    }
  }

  private func handleFolderCall(_ call: FlutterMethodCall,
                                _ result: @escaping FlutterResult) {
    switch call.method {
    case "pickDirectory":
      if folderPickerResult != nil {
        result(nil) // sélection déjà en cours
        return
      }
      // Le sélecteur de DOSSIER (forOpeningContentTypes:/UTType.folder) est
      // disponible à partir d'iOS 14. Sur iOS 13 (très marginal), on renvoie
      // une erreur propre côté Dart.
      if #available(iOS 14.0, *) {
        folderPickerResult = result
        DispatchQueue.main.async {
          let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.folder], asCopy: false)
          picker.delegate = self
          picker.allowsMultipleSelection = false
          self.topViewController()?.present(picker, animated: true)
        }
      } else {
        result(FlutterError(
          code: "UNSUPPORTED",
          message: "La sélection d'un dossier de sauvegarde nécessite iOS 14 ou plus récent.",
          details: nil))
      }
    case "startAccess":
      guard let args = call.arguments as? [String: Any],
            let bookmark = args["bookmark"] as? String,
            let data = Data(base64Encoded: bookmark) else {
        result(FlutterError(code: "BAD_ARGS",
                            message: "bookmark manquant ou invalide", details: nil))
        return
      }
      do {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        if url.startAccessingSecurityScopedResource() {
          scopedFolderURLs[bookmark] = url
          result(["path": url.path, "stale": stale])
        } else {
          result(FlutterError(code: "ACCESS_DENIED",
                              message: "Accès refusé au dossier de sauvegarde",
                              details: nil))
        }
      } catch {
        result(FlutterError(code: "RESOLVE_FAILED",
                            message: error.localizedDescription, details: nil))
      }
    case "stopAccess":
      if let args = call.arguments as? [String: Any],
         let bookmark = args["bookmark"] as? String,
         let url = scopedFolderURLs.removeValue(forKey: bookmark) {
        url.stopAccessingSecurityScopedResource()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - UIDocumentPickerDelegate

  func documentPicker(_ controller: UIDocumentPickerViewController,
                      didPickDocumentsAt urls: [URL]) {
    let cb = folderPickerResult
    folderPickerResult = nil
    guard let url = urls.first else { cb?(nil); return }
    let started = url.startAccessingSecurityScopedResource()
    defer { if started { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try url.bookmarkData(options: [],
                                      includingResourceValuesForKeys: nil,
                                      relativeTo: nil)
      cb?(["path": url.path, "bookmark": data.base64EncodedString()])
    } catch {
      cb?(["path": url.path, "bookmark": ""])
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let cb = folderPickerResult
    folderPickerResult = nil
    cb?(nil)
  }

  private func topViewController() -> UIViewController? {
    var top = self.window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
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
