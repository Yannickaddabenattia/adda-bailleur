import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {

  static var incomingFileChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "adda_location/incoming_file",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "consumePending" {
        let appDelegate = NSApplication.shared.delegate as? AppDelegate
        result(appDelegate?.consumePendingFilePath())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    MainFlutterWindow.incomingFileChannel = channel

    // Mail compose via NSSharingService — fonctionne en sandbox (pas
    // besoin d'Apple Events). Ouvre Mail.app avec destinataire, sujet,
    // corps et pièce jointe pré-remplis.
    let mailChannel = FlutterMethodChannel(
      name: "adda_location/mail",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    mailChannel.setMethodCallHandler { call, result in
      if call.method == "composeEmail" {
        guard let args = call.arguments as? [String: Any],
              let to = args["to"] as? String,
              let subject = args["subject"] as? String,
              let body = args["body"] as? String,
              let attachmentPath = args["attachmentPath"] as? String,
              let service = NSSharingService(named: .composeEmail) else {
          result(FlutterError(code: "MAIL_UNAVAILABLE",
                              message: "NSSharingService composeEmail indisponible.",
                              details: nil))
          return
        }
        service.recipients = to.isEmpty ? nil : [to]
        service.subject = subject
        let url = URL(fileURLWithPath: attachmentPath)
        let items: [Any] = [body as NSString, url]
        if service.canPerform(withItems: items) {
          service.perform(withItems: items)
          result(nil)
        } else {
          result(FlutterError(code: "MAIL_CANNOT_PERFORM",
                              message: "Mail.app refuse la composition. Configurez un compte mail.",
                              details: nil))
        }
      } else if call.method == "revealInFinder" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "BAD_ARGS",
                              message: "path manquant", details: nil))
          return
        }
        NSWorkspace.shared.activateFileViewerSelecting(
          [URL(fileURLWithPath: path)]
        )
        result(nil)
      } else if call.method == "saveFileAs" {
        guard let args = call.arguments as? [String: Any],
              let sourcePath = args["sourcePath"] as? String,
              let suggestedName = args["suggestedName"] as? String else {
          result(FlutterError(code: "BAD_ARGS",
                              message: "sourcePath/suggestedName manquants",
                              details: nil))
          return
        }
        DispatchQueue.main.async {
          let panel = NSSavePanel()
          panel.title = "Enregistrer le partage"
          panel.nameFieldStringValue = suggestedName
          panel.canCreateDirectories = true
          panel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory, in: .userDomainMask
          ).first
          panel.begin { response in
            guard response == .OK, let dest = panel.url else {
              result(nil)
              return
            }
            do {
              if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
              }
              try FileManager.default.copyItem(
                at: URL(fileURLWithPath: sourcePath),
                to: dest
              )
              result(dest.path)
            } catch {
              result(FlutterError(code: "SAVE_FAILED",
                                  message: error.localizedDescription,
                                  details: nil))
            }
          }
        }
      } else if call.method == "shareFile" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "BAD_ARGS",
                              message: "path manquant", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        let picker = NSSharingServicePicker(items: [url])
        DispatchQueue.main.async {
          if let window = NSApplication.shared.windows.first,
             let contentView = window.contentView {
            let rect = NSRect(
              x: contentView.bounds.midX - 1,
              y: contentView.bounds.midY - 1,
              width: 2, height: 2
            )
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
          }
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // ─── Sauvegarde auto : dossier externe choisi + security-scoped bookmark ───
    // Permet d'écrire durablement dans un dossier de l'utilisateur (pCloud
    // Drive, disque virtuel monté, NAS, OneDrive…) et de conserver l'accès
    // après relance de l'app, ce que le bac à sable exige.
    var scopedURLs: [String: URL] = [:] // bookmark base64 -> URL en cours d'accès
    let folderChannel = FlutterMethodChannel(
      name: "adda_location/secure_folder",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    folderChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "pickDirectory":
        DispatchQueue.main.async {
          let panel = NSOpenPanel()
          panel.title = "Choisir le dossier de sauvegarde"
          panel.message = "Sélectionnez un dossier (pCloud, disque, NAS…) où "
            + "ADDA Bailleur écrira ses sauvegardes chiffrées."
          panel.canChooseFiles = false
          panel.canChooseDirectories = true
          panel.allowsMultipleSelection = false
          panel.canCreateDirectories = true
          panel.begin { response in
            guard response == .OK, let url = panel.url else {
              result(nil)
              return
            }
            do {
              let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
              )
              result(["path": url.path, "bookmark": data.base64EncodedString()])
            } catch {
              // Bookmark impossible : on renvoie au moins le chemin (accès
              // valable pour la session courante).
              result(["path": url.path, "bookmark": ""])
            }
          }
        }
      case "startAccess":
        guard let args = call.arguments as? [String: Any],
              let bookmark = args["bookmark"] as? String,
              let data = Data(base64Encoded: bookmark) else {
          result(FlutterError(code: "BAD_ARGS",
                              message: "bookmark manquant ou invalide",
                              details: nil))
          return
        }
        do {
          var stale = false
          let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
          )
          if url.startAccessingSecurityScopedResource() {
            scopedURLs[bookmark] = url
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
           let url = scopedURLs.removeValue(forKey: bookmark) {
          url.stopAccessingSecurityScopedResource()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
