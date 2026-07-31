//
//  SoundManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/8/26.
//
import AVFoundation
import OSLog


class SoundManager {

    static let shared = SoundManager()

    private var player: AVAudioPlayer?


    func playNoot() {

        guard let url = Bundle.main.url(
            forResource: "nootnoot",
            withExtension: "mp3"
        )
        else {
            Log.audio.error("nootnoot.mp3 not found in bundle — check it's still included in the target's build phase")
            return
        }

        do {

            player = try AVAudioPlayer(
                contentsOf: url
            )

            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()

        }
        catch {

            Log.audio.error("Failed to play nootnoot.mp3: \(error)")

        }
    }
}
