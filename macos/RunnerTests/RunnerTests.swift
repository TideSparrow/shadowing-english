import Cocoa
import AVFoundation
import FlutterMacOS
import XCTest
@testable import 语言避难所

@MainActor
class RunnerTests: XCTestCase {
  private let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]

  func testEverySpeedKeepsSynthesisNormalAndUsesPlaybackRate() {
    let speech = FakeSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let normal = speech.rate
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    var results: [Bool] = []
    for rate in speeds + [1] {
      controller.speak("projects", language: "en-US", voice: "", rate: rate) { results.append($0 as! Bool) }
      XCTAssertEqual(speech.rate, normal)
      speech.finish(true)
      XCTAssertEqual(audio.rates.last, Float(rate))
      XCTAssertEqual(results.count, audio.rates.count - 1)
      audio.finish()
      XCTAssertEqual(results.last, true)
    }
    XCTAssertEqual(results.count, speeds.count + 1)
  }

  func testRequestWaitsForAudioPlaybackAndRemovesTemporarySpeech() throws {
    let speech = FakeSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    var results: [Bool] = []
    controller.speak("projects", language: "en-US", voice: "", rate: 1) { results.append($0 as! Bool) }
    let url = try XCTUnwrap(speech.lastURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(results.isEmpty)
    speech.finish(true)
    XCTAssertTrue(results.isEmpty)
    audio.finish()
    XCTAssertEqual(results, [true])
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testReplacementWaitsForRenderCancellationAndKeepsOnlyLatestRequest() {
    let speech = FakeSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    var results: [String] = []
    controller.speak("first", language: "en-US", voice: "", rate: 1) { _ in results.append("first") }
    controller.speak("second", language: "en-US", voice: "", rate: 2) { _ in results.append("second") }
    controller.speak("third", language: "en-US", voice: "", rate: 3) { _ in results.append("third") }
    XCTAssertEqual(speech.stopCount, 1)
    XCTAssertEqual(speech.texts, ["first"])
    XCTAssertEqual(results, ["second"])
    speech.finish(false)
    XCTAssertEqual(speech.texts, ["first", "third"])
    XCTAssertEqual(results, ["second", "first"])
    speech.finish(true)
    XCTAssertEqual(audio.rates, [3])
    audio.finish()
    XCTAssertEqual(results, ["second", "first", "third"])
  }

  func testStopWhileRenderingResolvesPendingRequestsWithoutPlayingThem() {
    let speech = FakeSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    var results: [Bool] = []
    controller.speak("first", language: "en-US", voice: "", rate: 1) { results.append($0 as! Bool) }
    controller.speak("second", language: "en-US", voice: "", rate: 3) { results.append($0 as! Bool) }
    controller.stop()
    XCTAssertEqual(results, [true])
    speech.finish(false)
    XCTAssertEqual(results, [true, true])
    XCTAssertTrue(audio.rates.isEmpty)
  }

  func testStoppedPlaybackCannotCompleteTheNextRequest() {
    let speech = FakeSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    var results: [String] = []
    controller.speak("first", language: "en-US", voice: "", rate: 0.5) { _ in results.append("first") }
    speech.finish(true)
    controller.stop()
    XCTAssertEqual(results, ["first"])
    controller.speak("second", language: "en-US", voice: "", rate: 3) { _ in results.append("second") }
    audio.finish(index: 0)
    XCTAssertEqual(results, ["first"])
    speech.finish(true)
    audio.finish()
    XCTAssertEqual(results, ["first", "second"])
  }

  func testSynthesisAndPlaybackFailuresReportFailureAndCleanUp() {
    let speech = FakeSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    var results: [Bool] = []
    speech.canStart = false
    controller.speak("projects", language: "en-US", voice: "", rate: 1) { results.append($0 as! Bool) }
    XCTAssertEqual(results, [false])
    speech.canStart = true
    audio.shouldFail = true
    controller.speak("projects", language: "en-US", voice: "", rate: 3) { results.append($0 as! Bool) }
    speech.finish(true)
    XCTAssertEqual(results, [false, false])
    if let url = speech.lastURL { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
    audio.shouldFail = false
    controller.speak("projects", language: "en-US", voice: "", rate: 1) { results.append($0 as! Bool) }
    speech.finish(false)
    XCTAssertEqual(results, [false, false, false])
  }

  func testInvalidRatesNeverStartSpeech() {
    let speech = FakeSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    for rate in [0.1, 3.1, Double.nan, Double.infinity] {
      controller.speak("projects", language: "en-US", voice: "", rate: rate) { XCTAssertEqual($0 as? Bool, false) }
    }
    XCTAssertTrue(speech.texts.isEmpty)
  }

  func testNaturalVoiceSelectionRespectsLanguageQualityAndExplicitChoice() {
    let voices = [
      NativeTtsVoice(id: "us-standard", name: "US standard", language: "en-US", quality: 1),
      NativeTtsVoice(id: "us-enhanced", name: "US enhanced", language: "en-US", quality: 2),
      NativeTtsVoice(id: "in-premium", name: "India premium", language: "en-IN", quality: 3),
      NativeTtsVoice(id: "chinese", name: "Chinese", language: "zh-CN", quality: 3)
    ]
    XCTAssertEqual(NativeTtsVoices.select(from: voices, language: "en-US", selectedID: "")?.id, "us-enhanced")
    XCTAssertEqual(NativeTtsVoices.select(from: voices, language: "en-US", selectedID: "us-standard")?.id, "us-standard")
    XCTAssertEqual(NativeTtsVoices.select(from: voices, language: "en-US", selectedID: "in-premium")?.id, "in-premium")
    XCTAssertEqual(NativeTtsVoices.select(from: voices, language: "zh-CN", selectedID: "us-standard")?.id, "chinese")
    XCTAssertNil(NativeTtsVoices.select(from: voices, language: "fr-FR", selectedID: ""))
    XCTAssertEqual(voices[2].label, "India premium · en-IN · 高品质")
  }

  func testInstalledVoicesExcludeNoveltyAndLegacyRoboticVoices() throws {
    let voices = NativeTtsVoices.installed()
    let selected = try XCTUnwrap(NativeTtsVoices.select(from: voices, language: "en-US", selectedID: ""))
    XCTAssertTrue(selected.language.hasPrefix("en-"))
    for voice in voices {
      XCTAssertFalse(voice.id.hasPrefix("com.apple.eloquence."))
      XCTAssertFalse(voice.id.hasPrefix("com.apple.speech.synthesis.voice.") && voice.id != AVSpeechSynthesisVoiceIdentifierAlex)
      if #available(macOS 14.0, *), let metadata = AVSpeechSynthesisVoice(identifier: voice.id) {
        XCTAssertFalse(metadata.voiceTraits.contains(.isNoveltyVoice))
      }
    }
    print("TTS_NORMAL_DEFAULT \(selected.id) \(selected.label)")
  }


  func testRealEnglishSpeechIncludesProjectsAndSentenceEnding() throws {
    for (name, text) in [
      ("projects", "projects"), ("uppercase", "PROJECTS"),
      ("sentence", "I have three projects to finish today.")
    ] {
      let (url, words) = try renderNormalSpeech(name: name, text: text)
      XCTAssertTrue(words.contains { $0.lowercased() == "projects" }, "Words: \(words)")
      if name == "sentence" { XCTAssertTrue(words.contains { $0.lowercased() == "today" }) }
      let audio = try AVAudioFile(forReading: url)
      XCTAssertGreaterThan(Double(audio.length) / audio.processingFormat.sampleRate, 0.5)
    }
  }

  func testAllEightActualAudioSpeedRatios() throws {
    let (source, _) = try renderNormalSpeech(name: "speed-source", text:
      "Hello! I have three projects to finish today. We can read this sentence at a comfortable and natural speaking speed.")
    let directory = source.deletingLastPathComponent()
    var durations: [String: Double] = [:]
    for rate in speeds {
      let audio = try stretch(source: source, rate: Float(rate))
      durations[String(rate)] = audio.duration
      try audio.write(to: directory.appendingPathComponent("speed-\(rate).caf"))
    }
    let normal = try XCTUnwrap(durations["1.0"])
    for rate in speeds {
      let expected = normal / rate
      XCTAssertEqual(try XCTUnwrap(durations[String(rate)]), expected,
        accuracy: max(0.05, expected * 0.02), "Actual audio duration must follow the requested speed: \(rate)")
    }
    try JSONSerialization.data(withJSONObject: durations, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("speed-durations.json"))
  }

  func testHalfAndTripleSpeedKeepPitchUnchanged() throws {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1))
    let frames = AVAudioFrameCount(22050 * 3)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let channel = try XCTUnwrap(buffer.floatChannelData?[0])
    for index in 0..<Int(frames) { channel[index] = Float(0.2 * sin(2 * .pi * 440 * Double(index) / 22050)) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-pitch-test.caf")
    do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
    defer { try? FileManager.default.removeItem(at: url) }
    for rate: Float in [0.5, 1, 3] {
      let rendered = try stretch(source: url, rate: rate)
      let start = rendered.samples.count / 3, end = rendered.samples.count * 2 / 3
      var crossings = 0
      for index in (start + 1)..<end where rendered.samples[index - 1] <= 0 && rendered.samples[index] > 0 { crossings += 1 }
      let frequency = Double(crossings) * rendered.sampleRate / Double(end - start)
      XCTAssertEqual(frequency, 440, accuracy: 10, "Speed changes must preserve pitch")
    }
  }

  func testRealPlaybackCompletionAtHalfAndTripleSpeed() throws {
    let (source, _) = try renderNormalSpeech(name: "playback-source", text:
      "Hello! I have three projects to finish today.")
    let file = try AVAudioFile(forReading: source)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    for rate: Float in [0.5, 3] {
      let player = SpeechAudioPlayer()
      let complete = expectation(description: "actual playback at \(rate)")
      let started = ProcessInfo.processInfo.systemUptime
      try player.play(file: source, rate: rate) { complete.fulfill() }
      wait(for: [complete], timeout: duration / Double(rate) + 5)
      let elapsed = ProcessInfo.processInfo.systemUptime - started
      player.stop()
      XCTAssertGreaterThan(elapsed, duration / Double(rate) - 0.15)
      XCTAssertLessThan(elapsed, duration / Double(rate) + 1)
    }
  }

  private func renderNormalSpeech(name: String, text: String) throws -> (URL, [String]) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-exact-speed", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("\(name).aiff")
    try? FileManager.default.removeItem(at: destination)
    let speech = NSSpeechSynthesizer(), audio = FakeSpeechPlayback()
    let controller = NativeTtsController(synthesizer: speech, playback: audio)
    let observer = RecordingSpeechDelegate(controller: controller)
    speech.delegate = observer
    let completed = expectation(description: "render \(name)")
    audio.onPlay = { source in
      try FileManager.default.copyItem(at: source, to: destination)
      audio.finish()
    }
    controller.speak(text, language: "en-GB", voice: "", rate: 1) {
      XCTAssertEqual($0 as? Bool, true)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 25)
    XCTAssertTrue(observer.errors.isEmpty, observer.errors.joined(separator: ", "))
    return (destination, observer.words)
  }

  private struct RenderedAudio {
    let samples: [Float]
    let sampleRate: Double
    var duration: Double { Double(samples.count) / sampleRate }
    func write(to url: URL) throws {
      let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
      buffer.frameLength = AVAudioFrameCount(samples.count)
      let data = try XCTUnwrap(buffer.floatChannelData?[0])
      for (index, value) in samples.enumerated() { data[index] = value }
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      try file.write(from: buffer)
    }
  }

  private func stretch(source: URL, rate: Float) throws -> RenderedAudio {
    let input = try AVAudioFile(forReading: source)
    let graph = SpeechAudioPlayer.makeGraph(format: input.processingFormat, rate: rate)
    XCTAssertEqual(graph.timePitch.rate, rate)
    XCTAssertEqual(graph.timePitch.pitch, 0)
    try graph.engine.enableManualRenderingMode(.offline, format: input.processingFormat, maximumFrameCount: 1024)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat, frameCapacity: 1024))
    graph.player.scheduleFile(input, at: nil)
    try graph.engine.start()
    graph.player.play()
    defer { graph.player.stop(); graph.engine.stop() }
    let maximum = Int(Double(input.length) / Double(rate) + input.processingFormat.sampleRate)
    var samples: [Float] = []
    var retries = 0
    while samples.count < maximum {
      let status = try graph.engine.renderOffline(1024, to: buffer)
      if status == .cannotDoInCurrentContext {
        retries += 1
        if retries > 1000 { throw NSError(domain: "OfflineAudioRetry", code: 1) }
        continue
      }
      guard status == .success, let channel = buffer.floatChannelData?[0] else {
        throw NSError(domain: "OfflineAudio", code: 1)
      }
      samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
    // Measure the produced waveform itself, excluding only silence at its edges.
    let first = try XCTUnwrap(samples.firstIndex { abs($0) > 0.0001 })
    let last = try XCTUnwrap(samples.lastIndex { abs($0) > 0.0001 })
    return RenderedAudio(samples: Array(samples[first...last]), sampleRate: input.processingFormat.sampleRate)
  }
}

private class FakeSpeechSynthesizer: NSSpeechSynthesizer {
  var texts: [String] = []
  var lastURL: URL?
  var stopCount = 0
  var canStart = true
  override func setVoice(_ voice: NSSpeechSynthesizer.VoiceName?) -> Bool { true }
  override func startSpeaking(_ text: String, to url: URL) -> Bool {
    texts.append(text)
    lastURL = url
    if canStart { try? Data([1, 2, 3]).write(to: url) }
    return canStart
  }
  override func stopSpeaking() { stopCount += 1 }
  @MainActor func finish(_ success: Bool) { delegate?.speechSynthesizer?(self, didFinishSpeaking: success) }
}

private class FakeSpeechPlayback: SpeechAudioPlayback {
  var rates: [Float] = []
  var completions: [() -> Void] = []
  var onPlay: ((URL) throws -> Void)?
  var shouldFail = false
  func play(file: URL, rate: Float, completion: @escaping () -> Void) throws {
    if shouldFail { throw NSError(domain: "Playback", code: 1) }
    rates.append(rate)
    completions.append(completion)
    try onPlay?(file)
  }
  func stop() {}
  @MainActor func finish(index: Int? = nil) {
    completions[index ?? completions.count - 1]()
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  }
}

@MainActor
private class RecordingSpeechDelegate: NSObject, NSSpeechSynthesizerDelegate {
  let controller: NativeTtsController
  var words: [String] = []
  var errors: [String] = []
  init(controller: NativeTtsController) { self.controller = controller }
  func speechSynthesizer(_ sender: NSSpeechSynthesizer, willSpeakWord range: NSRange, of string: String) {
    words.append((string as NSString).substring(with: range).trimmingCharacters(in: .punctuationCharacters))
  }
  func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking success: Bool) {
    controller.speechSynthesizer(sender, didFinishSpeaking: success)
  }
  func speechSynthesizer(_ sender: NSSpeechSynthesizer, didEncounterErrorAt index: Int, of string: String, message: String) {
    errors.append(message)
  }
}
