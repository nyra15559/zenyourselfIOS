import Foundation
import AVFoundation
import Speech
import Flutter

/// iOS Bridge für Streaming-STT:
/// MethodChannel  "zen.whisper"          → start/pause/resume/stop
/// EventChannel   "zen.whisper/events"   → {type: partial|final|level, value: any}
final class WhisperBridge: NSObject, FlutterStreamHandler {

  // MARK: - Public registration
  static func register(with messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(name: "zen.whisper", binaryMessenger: messenger)
    let events = FlutterEventChannel(name: "zen.whisper/events", binaryMessenger: messenger)

    let instance = WhisperBridge()
    events.setStreamHandler(instance)

    method.setMethodCallHandler { [weak instance] call, result in
      guard let bridge = instance else { result(FlutterError(code: "disposed", message: "Bridge gone", details: nil)); return }
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        let localeStr = (args?["locale"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        bridge.start(localeIdentifier: localeStr) { ok, err in
          if let err = err { result(FlutterError(code: "start_failed", message: err, details: nil)) }
          else { result(ok) }
        }
      case "pause":
        bridge.pause()
        result(true)
      case "resume":
        bridge.resume()
        result(true)
      case "stop":
        bridge.stop()
        result(nil) // iOS liefert keinen Pfad zurück – Dart erwartet optional String?
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - StreamHandler
  private var sink: FlutterEventSink?
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: - Speech engine
  private var audioEngine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var isActive = false
  private var isPaused = false

  // MARK: - Start / Stop / Pause / Resume
  func start(localeIdentifier: String?, complete: @escaping (Bool, String?) -> Void) {
    if isActive {
      complete(true, nil)
      return
    }

    requestPermissions { [weak self] granted, errorMsg in
      guard let self = self else { complete(false, "bridge disposed"); return }
      guard granted else { complete(false, errorMsg ?? "permission denied"); return }

      // Locale bestimmen (z. B. "de-CH" → CH-Deutsch; Fallback: Gerätesprache)
      let locId = (localeIdentifier?.isEmpty == false ? localeIdentifier! : (Locale.preferredLanguages.first ?? "de-CH"))
      self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: locId)) ?? SFSpeechRecognizer()
      self.request = SFSpeechAudioBufferRecognitionRequest()
      guard let request = self.request, let recognizer = self.recognizer else {
        complete(false, "request/recognizer unavailable"); return
      }
      request.shouldReportPartialResults = true
      request.taskHint = .dictation

      // Audio-Session
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
      } catch {
        complete(false, "audio session error: \(error.localizedDescription)")
        return
      }

      // Tap für Input + Pegelberechnung
      let input = self.audioEngine.inputNode
      let fmt = input.outputFormat(forBus: 0)
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
        guard let self = self else { return }
        request.append(buffer)
        self.pushLevel(buffer: buffer)
      }

      // Recognition-Task
      self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        guard let self = self else { return }
        if let result = result {
          let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty {
            if result.isFinal {
              self.emit(type: "final", value: text)
            } else {
              self.emit(type: "partial", value: text)
            }
          }
        }
        if error != nil {
          // Ruhiger Abschluss bei Fehler
          self.stop()
        }
      }

      // Engine starten
      self.audioEngine.prepare()
      do {
        try self.audioEngine.start()
      } catch {
        complete(false, "audio engine start failed: \(error.localizedDescription)")
        return
      }

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
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch { /* ignore */ }
  }

  func pause() {
    guard isActive else { return }
    isPaused = true
    // Wir lassen Audio/Task laufen (flüssigere Fortsetzung); Level wird gedämpft.
  }

  func resume() {
    guard isActive else { return }
    isPaused = false
  }

  // MARK: - Permissions
  private func requestPermissions(_ cb: @escaping (Bool, String?) -> Void) {
    // Mic
    AVAudioSession.sharedInstance().requestRecordPermission { micOK in
      if !micOK { cb(false, "microphone permission denied"); return }
      // Speech
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

  // MARK: - Events
  private func emit(type: String, value: Any) {
    guard let sink = sink else { return }
    sink(["type": type, "value": value])
  }

  // Pegel 0..1 aus PCM-Buffer (RMS → dB → linear)
  private func pushLevel(buffer: AVAudioPCMBuffer) {
    guard let ch = buffer.floatChannelData?.pointee else { return }
    let frameCount = Int(buffer.frameLength)
    if frameCount == 0 { return }

    var sum: Float = 0.0
    var i = 0
    while i < frameCount {
      let v = ch[i]
      sum += v * v
      i += 1
    }
    let rms = sqrtf(sum / Float(max(frameCount, 1)))
    var db = 20.0 * log10(Double(max(rms, 1e-7)))
    // dB-Range (-50..0) → 0..1
    db = min(0.0, max(-50.0, db))
    var level = (db + 50.0) / 50.0
    if isPaused { level = 0.04 }
    emit(type: "level", value: level)
  }
}
