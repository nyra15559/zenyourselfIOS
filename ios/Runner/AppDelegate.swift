import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  var window: UIWindow?
  lazy var flutterEngine = FlutterEngine(name: "zen_engine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Flutter Engine starten und Plugins registrieren
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    // Flutter ViewController programmatic als Root setzen
    let flutterVC = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    self.window = UIWindow(frame: UIScreen.main.bounds)
    self.window?.rootViewController = flutterVC
    self.window?.makeKeyAndVisible()

    // Wichtig: Super aufrufen für Plugin-Callbacks (Push, etc.)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
