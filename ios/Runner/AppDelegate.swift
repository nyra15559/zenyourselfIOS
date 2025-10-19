import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {

  // Keine eigene 'var window' anlegen – ist in der Superklasse vorhanden.
  lazy var flutterEngine = FlutterEngine(name: "zen_engine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Flutter Engine starten und Plugins registrieren
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    // iOS Bridges registrieren (Method/EventChannels)
    WhisperBridge.register(with: flutterEngine.binaryMessenger) // STT
    TtsBridge.register(with: flutterEngine.binaryMessenger)      // TTS  ← NEU

    // Programmatic UIWindow + FlutterViewController
    let win = UIWindow(frame: UIScreen.main.bounds)
    let flutterVC = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    win.rootViewController = flutterVC
    win.makeKeyAndVisible()
    self.window = win   // vorhandene Property der Superklasse verwenden

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
