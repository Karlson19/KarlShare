import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  // Retained for the app lifetime so their channels stay registered.
  private var transferEngine: TransferEngine?
  private var discovery: DiscoveryService?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // A registrar gives us a binary messenger regardless of the scene setup.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KarlshareNative") else {
      return
    }
    let messenger = registrar.messenger()

    let deviceId = AppDelegate.stableDeviceId()
    let saveDir = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Karlshare", isDirectory: true)

    let engine = TransferEngine(messenger: messenger, localDeviceId: deviceId)
    let disco = DiscoveryService(
      messenger: messenger,
      saveDir: saveDir,
      transferEmit: { [weak engine] type, body in engine?.emitTransfer(type, body) })

    // Route mc:-addressed sends from the transfer channel to Multipeer.
    engine.onMultipeerSend = { [weak disco] key, files, transferId in
      disco?.sendViaMultipeer(peerKey: key, files: files, transferId: transferId)
    }

    self.transferEngine = engine
    self.discovery = disco
  }

  /// Stable per-install device UUID — mirrors the Android `deviceId()` in
  /// MainActivity so the same device keeps its identity across launches.
  private static func stableDeviceId() -> UUID {
    let key = "karlshare_device_id"
    let defaults = UserDefaults.standard
    if let s = defaults.string(forKey: key), let u = UUID(uuidString: s) { return u }
    let u = UUID()
    defaults.set(u.uuidString, forKey: key)
    return u
  }
}
