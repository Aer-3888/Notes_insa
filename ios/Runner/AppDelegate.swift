import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register the native data-layer bridge (mirrors MainActivity.kt).
    if let controller = window?.rootViewController as? FlutterViewController {
      GradesBridge.register(with: controller.binaryMessenger)
    }

    // Register the background fetch task handler. Must happen before launch
    // finishes; scheduling itself is driven from Dart via InitBackgroundTask.
    if #available(iOS 13.0, *) {
      GradesBackgroundTask.register()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
