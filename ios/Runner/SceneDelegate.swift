import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(_ scene: UIScene,
                      openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    forwardURLs(URLContexts)
  }

  override func scene(_ scene: UIScene,
                      willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    let urls = connectionOptions.urlContexts
    if !urls.isEmpty {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.forwardURLs(urls)
      }
    }
  }

  private func forwardURLs(_ URLContexts: Set<UIOpenURLContext>) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }
    for ctx in URLContexts {
      appDelegate.forwardFile(ctx.url)
    }
  }
}
