//
//  SoundManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/8/26.
//
import AVFoundation


class SoundManager {

    static let shared = SoundManager()

    private var player: AVAudioPlayer?


    func playNoot() {

        print("Attempting NOOT")


        guard let url = Bundle.main.url(
            forResource: "nootnoot",
            withExtension: "mp3"
        )
        else {
            print("❌ NOOT FILE NOT FOUND")
            return
        }


        print("✅ Found sound:", url)


        do {

            player = try AVAudioPlayer(
                contentsOf: url
            )

            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()

            print("✅ NOOT PLAYING")

        }
        catch {

            print("❌ Audio error:", error)

        }
    }
}
