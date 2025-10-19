import UIKit
import Flutter
import AVFoundation
import Speech

@main
class AppDelegate: FlutterAppDelegate {

  // Keine eigene 'var window' deklarieren – steckt in der Superklasse.
  lazy var flutterEngine = FlutterEngine(name: "zen_engine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Flutter Engine starten und Plugins registrieren
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    // Bridges (STT + TTS) registrieren
    WhisperBridge.register(with: flutterEngine.binaryMessenger)
    TtsBridge.register(with: flutterEngine.binaryMessenger)

    // Programmatic UIWindow + FlutterViewController
    let win = UIWindow(frame: UIScreen.main.bounds)
    let flutterVC = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    win.rootViewController = flutterVC
    win.makeKeyAndVisible()
    self.window = win

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

//
// MARK: - WhisperBridge (Streaming STT via SFSpeechRecognizer)
// MethodChannel: "zen.whisper" (start/pause/resume/stop)
// EventChannel:  "zen.whisper/events" -> {type: partial|final|level, value: any}
//
final class WhisperBridge: NSObject, FlutterStreamHandler {

  static func register(with messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(name: "zen.whisper", binaryMessenger: messenger)
    let events = FlutterEventChannel(name: "zen.whisper/events", binaryMessenger: messenger)

    let instance = WhisperBridge()
    events.setStreamHandler(instance)

    method.setMethodCallHandler { [weak instance] call, result in
      guard let bridge = instance else {
        result(FlutterError(code: "disposed", message: "Bridge gone", details: nil))
        return
      }
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        let localeStr = (args?["locale"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        bridge.start(localeIdentifier: localeStr) { ok, err in
          if let err = err { result(FlutterError(code: "start_failed", message: err, details: nil)) }
          else { result(ok) }
        }
      case "pause":
        bridge.pause();  result(true)
      case "resume":
        bridge.resume(); result(true)
      case "stop":
        bridge.stop();   result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Stream
  private var sink: FlutterEventSink?
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

  // Speech engine
  private var audioEngine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var isActive = false
  private var isPaused = false

  // Start/Stop/Pause/Resume
  func start(localeIdentifier: String?, complete: @escaping (Bool, String?) -> Void) {
    if isActive { complete(true, nil); return }

    requestPermissions { [weak self] granted, errorMsg in
      guard let self = self else { complete(false, "bridge disposed"); return }
      guard granted else { complete(false, errorMsg ?? "permission denied"); return }

      let locId = (localeIdentifier?.isEmpty == false ? localeIdentifier! : (Locale.preferredLanguages.first ?? "de-CH"))
      self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: locId)) ?? SFSpeechRecognizer()
      self.request = SFSpeechAudioBufferRecognitionRequest()
      guard let request = self.request, let recognizer = self.recognizer else {
        complete(false, "request/recognizer unavailable"); return
      }
      request.shouldReportPartialResults = true
      request.taskHint = .dictation

      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
      } catch { complete(false, "audio session error: \(error.localizedDescription)"); return }

      let input = self.audioEngine.inputNode
      let fmt = input.outputFormat(forBus: 0)
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
        guard let self = self else { return }
        request.append(buffer)
        self.pushLevel(buffer: buffer)
      }

      self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        guard let self = self else { return }
        if let result = result {
          let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty {
            if result.isFinal { self.emit(type: "final", value: text) }
            else { self.emit(type: "partial", value: text) }
          }
        }
        if error != nil { self.stop() }
      }

      self.audioEngine.prepare()
      do { try self.audioEngine.start() }
      catch { complete(false, "audio engine start failed: \(error.localizedDescription)"); return }

      self.isActive = true
      self.isPaused = false
      complete(true, nil)
    }
  }

  func stop() {
    guard isActive else { return }
    isActive = false
    isPaused = false

    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil

    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func pause() { guard isActive else { return }; isPaused = true }
  func resume() { guard isActive else { return }; isPaused = false }

  // Permissions
  private func requestPermissions(_ cb: @escaping (Bool, String?) -> Void) {
    AVAudioSession.sharedInstance().requestRecordPermission { micOK in
      if !micOK { cb(false, "microphone permission denied"); return }
      SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async {
          switch status {
          case .authorized: cb(true, nil)
          case .denied: cb(false, "speech permission denied")
          case .restricted: cb(false, "speech restricted")
          case .notDetermined: cb(false, "speech permission not determined")
          @unknown default: cb(false, "speech unknown")
          }
        }
      }
    }
  }

  // Events
  private func emit(type: String, value: Any) { sink?(["type": type, "value": value]) }

  // Pegel 0..1 aus PCM
  private func pushLevel(buffer: AVAudioPCMBuffer) {
    guard let ch = buffer.floatChannelData?.pointee else { return }
    let n = Int(buffer.frameLength); if n == 0 { return }
    var sum: Float = 0; for i in 0..<n { let v = ch[i]; sum += v*v }
    let rms = sqrtf(sum / Float(max(n, 1)))
    var db = 20.0 * log10(Double(max(rms, 1e-7)))
    db = min(0.0, max(-50.0, db))
    var level = (db + 50.0) / 50.0
    if isPaused { level = 0.04 }
    emit(type: "level", value: level)
  }
}

//
// MARK: - TtsBridge (AVSpeechSynthesizer)
// MethodChannel: "zen.tts" (speak/stop/isSpeaking)
//
final class TtsBridge: NSObject {

  private static let channelName = "zen.tts"
  private static let synth = AVSpeechSynthesizer()

  static func register(with messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "speak":
        let args = call.arguments as? [String: Any]
        let text = (args?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let locale = (args?["locale"] as? String) ?? "de-CH"
        guard !text.isEmpty else {
          result(FlutterError(code: "empty_text", message: "no text", details: nil)); return
        }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: locale)
        utt.rate = AVSpeechUtteranceDefaultSpeechRate
        utt.pitchMultiplier = 1.0
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        synth.speak(utt)
        result(true)

      case "stop":
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        result(nil)

      case "isSpeaking":
        result(synth.isSpeaking)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
