import Foundation
import AVFoundation
import Flutter

/// iOS TTS-Bridge für den Dart-Channel "zen.tts"
/// - Methoden: configure, speak, stop, pause, resume,
///             setLanguage, setRate, setPitch, setVolume
/// - Callbacks (Dart-seitig via MethodChannel.setMethodCallHandler):
///     onStart, onComplete, onError
final class TtsBridge: NSObject, AVSpeechSynthesizerDelegate {

  // MARK: Channel
  private var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "zen.tts", binaryMessenger: messenger)
    let instance = TtsBridge(channel: ch)
    ch.setMethodCallHandler { [weak instance] call, result in
      guard let tts = instance else {
        result(FlutterError(code: "disposed", message: "TTS bridge gone", details: nil))
        return
      }
      tts.handle(call: call, result: result)
    }
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    synthesizer.delegate = self
  }

  // MARK: Synthesizer + Defaults
  private let synthesizer = AVSpeechSynthesizer()

  private var defLang  = "de-DE"   // BCP-47
  private var defRate  = 0.5       // 0.0..1.0  (wird auf iOS-Rate gemappt)
  private var defPitch = 1.0       // 0.5..2.0
  private var defVol   = 1.0       // 0.0..1.0

  // MARK: API
  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      let args = call.arguments as? [String: Any]
      if let lang = args?["lang"] as? String { defLang = lang }
      if let rate = args?["rate"] as? Double { defRate = clamp(rate, 0, 1) }
      if let pitch = args?["pitch"] as? Double { defPitch = clamp(pitch, 0.5, 2.0) }
      if let vol = args?["volume"] as? Double { defVol = clamp(vol, 0, 1) }
      result(nil)

    case "speak":
      let args = call.arguments as? [String: Any]
      let text   = (args?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let lang   = (args?["lang"] as? String) ?? defLang
      let rate   = (args?["rate"] as? Double) ?? defRate
      let pitch  = (args?["pitch"] as? Double) ?? defPitch
      let volume = (args?["volume"] as? Double) ?? defVol
      let queue  = (args?["queue"] as? Bool) ?? false

      guard !text.isEmpty else { result(false); return }
      speak(text: text, lang: lang, rate: rate, pitch: pitch, volume: volume, queue: queue)
      result(true)

    case "stop":
      stop()
      result(nil)

    case "pause":
      _ = synthesizer.pauseSpeaking(at: .immediate)
      result(nil)

    case "resume":
      _ = synthesizer.continueSpeaking()
      result(nil)

    case "setLanguage":
      if let args = call.arguments as? [String: Any], let lang = args["lang"] as? String {
        defLang = lang
      }
      result(nil)

    case "setRate":
      if let args = call.arguments as? [String: Any], let rate = args["rate"] as? Double {
        defRate = clamp(rate, 0, 1)
      }
      result(nil)

    case "setPitch":
      if let args = call.arguments as? [String: Any], let p = args["pitch"] as? Double {
        defPitch = clamp(p, 0.5, 2.0)
      }
      result(nil)

    case "setVolume":
      if let args = call.arguments as? [String: Any], let v = args["volume"] as? Double {
        defVol = clamp(v, 0, 1)
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func speak(text: String, lang: String, rate: Double, pitch: Double, volume: Double, queue: Bool) {
    do {
      // dezente Mix-Session; andere Audioquellen leiser machen
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      // Kein Hard-Fail; wir melden ein onError nach Dart
      channel?.invokeMethod("onError", arguments: nil)
    }

    if !queue, synthesizer.isSpeaking {
      _ = synthesizer.stopSpeaking(at: .immediate)
    }

    let utt = AVSpeechUtterance(string: text)
    utt.voice  = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: defLang)
    utt.rate   = mapRate(rate)
    utt.pitchMultiplier = Float(clamp(pitch, 0.5, 2.0))
    utt.volume = Float(clamp(volume, 0.0, 1.0))

    channel?.invokeMethod("onStart", arguments: nil)
    synthesizer.speak(utt)
  }

  private func stop() {
    if synthesizer.isSpeaking {
      _ = synthesizer.stopSpeaking(at: .immediate)
    }
    do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } catch {}
  }

  // MARK: Delegate → Callbacks nach Dart
  func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    channel?.invokeMethod("onComplete", arguments: nil)
    // Session optional freigeben, wenn nichts mehr in der Queue ist
    if !s.isSpeaking {
      do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } catch {}
    }
  }

  func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    // als "complete" behandeln, damit Dart aufräumt
    channel?.invokeMethod("onComplete", arguments: nil)
  }

  // MARK: Utils
  private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    return max(lo, min(hi, v))
  }

  /// Mapping 0..1 → iOS-Rate (angenehmer Bereich)
  private func mapRate(_ x: Double) -> Float {
    let minR: Float = 0.35   // angenehm langsam
    let maxR: Float = 0.60   // zügig, aber verständlich
    let t = Float(clamp(x, 0, 1))
    return minR + (maxR - minR) * t
  }
}
