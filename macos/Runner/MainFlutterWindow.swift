import Cocoa
import AVFoundation
import FlutterMacOS
import MediaPlayer
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private let nativeTts = NativeTtsController()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 1024, height: 680)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }
    configureNativeTts(with: flutterViewController)
    configureSystemMediaControls(with: flutterViewController)

    super.awakeFromNib()
  }

  private func configureSystemMediaControls(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.shadowing.english/system_media_controls",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "updatePlaybackState",
            let arguments = call.arguments as? [String: Any],
            let isPlaying = arguments["isPlaying"] as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.updateSystemMediaPlaybackState(isPlaying: isPlaying)
      result(nil)
    }
    let commands = MPRemoteCommandCenter.shared()
    updateSystemMediaPlaybackState(isPlaying: false)
    commands.playCommand.isEnabled = true
    commands.pauseCommand.isEnabled = true
    commands.togglePlayPauseCommand.isEnabled = true
    commands.nextTrackCommand.isEnabled = true
    commands.previousTrackCommand.isEnabled = true
    commands.playCommand.addTarget { _ in
      channel.invokeMethod("play", arguments: nil)
      return .success
    }
    commands.pauseCommand.addTarget { _ in
      channel.invokeMethod("pause", arguments: nil)
      return .success
    }
    commands.togglePlayPauseCommand.addTarget { _ in
      channel.invokeMethod("toggle", arguments: nil)
      return .success
    }
    commands.nextTrackCommand.addTarget { _ in
      channel.invokeMethod("next", arguments: nil)
      return .success
    }
    commands.previousTrackCommand.addTarget { _ in
      channel.invokeMethod("previous", arguments: nil)
      return .success
    }
  }

  private func updateSystemMediaPlaybackState(isPlaying: Bool) {
    let infoCenter = MPNowPlayingInfoCenter.default()
    infoCenter.nowPlayingInfo = [
      MPMediaItemPropertyTitle: "英语学习",
      MPMediaItemPropertyArtist: "语言避难所",
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0
    ]
    infoCenter.playbackState = isPlaying ? .playing : .paused
  }

  private func configureNativeTts(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.shadowing.english/native_tts",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }

      switch call.method {
      case "speak":
        let arguments = call.arguments as? [String: Any]
        let text = (arguments?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
          result(true)
          return
        }
        self.nativeTts.speak(
          text,
          language: arguments?["language"] as? String ?? "en-US",
          voice: arguments?["voice"] as? String ?? "",
          rate: arguments?["rate"] as? Double ?? 0.75,
          result: result
        )
      case "stop":
        self.nativeTts.stop()
        result(true)
      case "getEngines":
        result(["defaultEngine": "", "engines": []])
      case "getVoices":
        let voices = NativeTtsVoices.installed()
          .filter { $0.language.hasPrefix("en-") }
          .map { ["id": $0.id, "label": $0.label] }
        result(["voices": voices])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

}

// Synthesize at the engine's normal speed, then change playback speed without changing pitch.
protocol SpeechAudioPlayback: AnyObject {
  func play(file: URL, rate: Float, completion: @escaping () -> Void) throws
  func stop()
}

final class SpeechAudioPlayer: SpeechAudioPlayback {
  struct Graph {
    let engine: AVAudioEngine
    let player: AVAudioPlayerNode
    let timePitch: AVAudioUnitTimePitch
  }

  private var graph: Graph?
  private var audioFile: AVAudioFile?

  static func makeGraph(format: AVAudioFormat, rate: Float) -> Graph {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    timePitch.rate = rate
    timePitch.pitch = 0
    engine.attach(player)
    engine.attach(timePitch)
    engine.connect(player, to: timePitch, format: format)
    engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    return Graph(engine: engine, player: player, timePitch: timePitch)
  }

  func play(file: URL, rate: Float, completion: @escaping () -> Void) throws {
    stop()
    let audio = try AVAudioFile(forReading: file)
    let graph = Self.makeGraph(format: audio.processingFormat, rate: rate)
    self.graph = graph
    audioFile = audio
    graph.player.scheduleFile(audio, at: nil, completionCallbackType: .dataPlayedBack) { _ in
      completion()
    }
    do {
      try graph.engine.start()
      graph.player.play()
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    graph?.player.stop()
    graph?.engine.stop()
    graph = nil
    audioFile = nil
  }
}

class NativeTtsController: NSObject, NSSpeechSynthesizerDelegate {
  private struct Request {
    let id = UUID()
    let text: String
    let language: String
    let voice: String
    let rate: Double
    let result: FlutterResult
  }

  private let synthesizer: NSSpeechSynthesizer
  private let normalRate: Float
  private let playback: SpeechAudioPlayback
  private var pending: Request?
  private var active: Request?
  private var audioURL: URL?
  private var rendering = false
  private var stopping = false

  init(
    synthesizer: NSSpeechSynthesizer = NSSpeechSynthesizer(),
    playback: SpeechAudioPlayback = SpeechAudioPlayer()
  ) {
    self.synthesizer = synthesizer
    normalRate = synthesizer.rate
    self.playback = playback
    super.init()
    synthesizer.delegate = self
  }

  func speak(
    _ text: String, language: String, voice: String, rate: Double,
    result: @escaping FlutterResult
  ) {
    guard rate.isFinite, (0.5...3).contains(rate) else {
      result(false)
      return
    }
    pending?.result(true)
    pending = Request(text: text, language: language, voice: voice, rate: rate, result: result)
    if active != nil {
      stopActive()
    } else {
      startPending()
    }
  }

  func stop() {
    let cancelled = pending
    pending = nil
    cancelled?.result(true)
    stopActive()
  }

  private func stopActive() {
    guard active != nil, !stopping else { return }
    stopping = true
    if rendering {
      synthesizer.stopSpeaking()
    } else {
      finishActive(success: true)
    }
  }

  private func startPending() {
    guard active == nil, let request = pending else { return }
    pending = nil
    guard let voice = NativeTtsVoices.select(
      from: NativeTtsVoices.installed(), language: request.language, selectedID: request.voice
    ), synthesizer.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: voice.id)) else {
      request.result(false)
      return
    }
    synthesizer.rate = normalRate
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("shadowing-speech-\(request.id.uuidString).aiff")
    active = request
    audioURL = url
    rendering = true
    if !synthesizer.startSpeaking(request.text, to: url) {
      finishActive(success: false)
    }
  }

  private func finishActive(success: Bool) {
    guard let request = active else { return }
    active = nil
    rendering = false
    stopping = false
    playback.stop()
    if let url = audioURL { try? FileManager.default.removeItem(at: url) }
    audioURL = nil
    request.result(success)
    startPending()
  }

  func speechSynthesizer(
    _ sender: NSSpeechSynthesizer,
    didFinishSpeaking finishedSpeaking: Bool
  ) {
    guard rendering, let request = active, let url = audioURL else { return }
    rendering = false
    if stopping || !finishedSpeaking {
      finishActive(success: stopping)
      return
    }
    do {
      try playback.play(file: url, rate: Float(request.rate)) { [weak self] in
        DispatchQueue.main.async {
          guard let self, self.active?.id == request.id else { return }
          self.finishActive(success: true)
        }
      }
    } catch {
      finishActive(success: false)
    }
  }
}


struct NativeTtsVoice {
  let id: String
  let name: String
  let language: String
  let quality: Int

  var label: String {
    let qualityLabel = quality >= 3 ? "高品质" : quality == 2 ? "增强" : "标准"
    return "\(name) · \(language) · \(qualityLabel)"
  }
}

enum NativeTtsVoices {
  static func installed() -> [NativeTtsVoice] {
    let supported = Set(NSSpeechSynthesizer.availableVoices.map { $0.rawValue })
    var seen = Set<String>()
    return AVSpeechSynthesisVoice.speechVoices().compactMap { voice in
      guard supported.contains(voice.identifier), seen.insert(voice.identifier).inserted else { return nil }
      if #available(macOS 14.0, *), voice.voiceTraits.contains(.isNoveltyVoice) { return nil }
      // Legacy character and Eloquence voices are unsuitable for natural language practice.
      if voice.identifier.hasPrefix("com.apple.eloquence.") { return nil }
      if voice.identifier.hasPrefix("com.apple.speech.synthesis.voice."),
         voice.identifier != AVSpeechSynthesisVoiceIdentifierAlex { return nil }
      return NativeTtsVoice(
        id: voice.identifier, name: voice.name, language: voice.language,
        quality: voice.quality.rawValue
      )
    }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }

  static func select(from voices: [NativeTtsVoice], language: String, selectedID: String) -> NativeTtsVoice? {
    let locale = language.replacingOccurrences(of: "_", with: "-").lowercased()
    let base = locale.split(separator: "-").first
    let matching = voices.filter { $0.language.lowercased().split(separator: "-").first == base }
    if let selected = matching.first(where: { $0.id == selectedID }) { return selected }
    let defaultID = AVSpeechSynthesisVoice(language: language)?.identifier
    return matching.sorted { left, right in
      let leftExact = left.language.lowercased() == locale
      let rightExact = right.language.lowercased() == locale
      if leftExact != rightExact { return leftExact }
      if left.quality != right.quality { return left.quality > right.quality }
      if (left.id == defaultID) != (right.id == defaultID) { return left.id == defaultID }
      return left.id < right.id
    }.first
  }
}
