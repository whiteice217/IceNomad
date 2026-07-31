//
//  NotificationSoundPlayer.swift
//  IceNomad
//
//  Plays the incoming-message sound per NotificationSettings. The two
//  built-in tones are synthesized in-memory rather than shipping extra
//  bundled audio assets — a couple of clean sine-wave "ice" tones fit
//  the arctic theme without needing sourced sound files. "Noot Noot"
//  reuses the penguin sound already bundled for the splash screen.
//

import AVFoundation
import OSLog

final class NotificationSoundPlayer {

    static let shared = NotificationSoundPlayer()

    private var filePlayer: AVAudioPlayer?

    private let engine = AVAudioEngine()
    private let tonePlayerNode = AVAudioPlayerNode()

    /// Fixed format for the tone player's connection, matching every
    /// buffer `playTone` ever creates. Connecting with `format: nil`
    /// instead (letting the engine infer it) crashed on both iOS and Mac
    /// Catalyst: at connect time the node hasn't produced any output yet,
    /// so the inferred format didn't actually match the 44.1kHz mono
    /// buffers scheduled later, and `scheduleBuffer` throws an
    /// uncatchable Objective-C exception (not a Swift `Error`) on a
    /// format mismatch — confirmed via a live crash report from both
    /// platforms pointing at this exact call.
    private static let toneFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {

        engine.attach(tonePlayerNode)
        engine.connect(tonePlayerNode, to: engine.mainMixerNode, format: Self.toneFormat)
    }


    func playIncomingMessageSound() {

        guard NotificationSettings.shared.soundEnabled else {
            return
        }

        switch NotificationSettings.shared.selectedSound {

        case .none:
            return

        case .nootNoot:
            playBundledFile(named: "nootnoot", extension: "mp3")

        case .iceChime:
            playTone(frequencies: [880, 1318.5], durations: [0.09, 0.16])

        case .glacierBlip:
            playTone(frequencies: [660], durations: [0.12])

        case .custom:
            playCustomSound()
        }
    }


    /// Plays a built-in or custom sound so Settings' "Preview" button can
    /// audition a choice without needing an incoming message.
    func preview(_ sound: NotificationSound) {

        switch sound {

        case .none:
            return

        case .nootNoot:
            playBundledFile(named: "nootnoot", extension: "mp3")

        case .iceChime:
            playTone(frequencies: [880, 1318.5], durations: [0.09, 0.16])

        case .glacierBlip:
            playTone(frequencies: [660], durations: [0.12])

        case .custom:
            playCustomSound()
        }
    }


    private func playBundledFile(named name: String, extension ext: String) {

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            Log.audio.error("\(name, privacy: .public).\(ext, privacy: .public) not found in bundle")
            return
        }

        playFile(at: url)
    }


    private func playCustomSound() {

        guard let url = NotificationSettings.shared.resolveCustomSoundURL() else {
            Log.audio.error("No custom notification sound resolved — nothing to play")
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            Log.audio.error("Couldn't access security-scoped custom notification sound")
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        playFile(at: url)
    }


    private func playFile(at url: URL) {

        do {

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.8
            player.prepareToPlay()
            player.play()

            filePlayer = player

        } catch {
            Log.audio.error("Failed to play notification sound at \(url.lastPathComponent, privacy: .public): \(error)")
        }
    }


    private func playTone(frequencies: [Double], durations: [Double]) {

        let sampleRate = Self.toneFormat.sampleRate
        let format = Self.toneFormat

        var samples: [Float] = []

        for (frequency, duration) in zip(frequencies, durations) {

            let frameCount = Int(sampleRate * duration)

            for i in 0..<frameCount {

                let t = Double(i) / sampleRate
                let envelope = sin(Double.pi * Double(i) / Double(frameCount))
                let sample = sin(2 * Double.pi * frequency * t) * envelope

                samples.append(Float(sample * 0.3))
            }
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        let channelData = buffer.floatChannelData![0]

        for (index, sample) in samples.enumerated() {
            channelData[index] = sample
        }

        do {

            if !engine.isRunning {
                try engine.start()
            }

        } catch {
            Log.audio.error("Failed to start audio engine for notification tone: \(error)")
            return
        }

        tonePlayerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        tonePlayerNode.play()
    }
}
