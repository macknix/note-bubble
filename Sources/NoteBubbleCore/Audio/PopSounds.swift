import AVFoundation
import Foundation

/// Plays a random pop when a bubble bursts.
///
/// Files live in the bundle as `pop-1.wav` … `pop-5.wav`. They are loaded once
/// into memory as `Data` — each is under 15KB — and a fresh `AVAudioPlayer` is
/// built per pop so two bursts in quick succession overlap instead of cutting
/// each other off.
@MainActor
final class PopSounds: ObservableObject {
    static let shared = PopSounds()

    /// Filenames are a contract with `Scripts/make-pop-sounds.py` and with anyone
    /// dropping in their own recordings: same names, any format AVFoundation reads.
    private static let names = (1...5).map { "pop-\($0)" }
    /// `wav` is deliberately last: it is the format `Scripts/make-pop-sounds.py`
    /// emits, so real recordings always win over synthesised fallbacks.
    private static let extensions = ["mp3", "m4a", "aiff", "caf", "wav"]

    private var clips: [Data] = []
    private var active: [AVAudioPlayer] = []
    private var lastIndex = -1

    /// Off is remembered across launches. `@Published` so the toolbar's speaker
    /// icon follows it directly instead of mirroring it into local view state.
    @Published var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: Self.muteDefaultsKey) }
    }

    private static let muteDefaultsKey = "PopSoundsMuted"

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.muteDefaultsKey)
        clips = Self.names.compactMap(Self.loadClip)
    }

    /// Looks for each name across the formats a drop-in replacement might use.
    ///
    /// `Bundle.main`, not `Bundle.module`: the `.app` is assembled by hand in
    /// `Scripts/build-app.sh`, which copies `Resources/Sounds` straight into
    /// `Contents/Resources/Sounds` rather than going through an SPM resource bundle.
    private static func loadClip(named name: String) -> Data? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds"),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }

    func play() {
        guard !isMuted, !clips.isEmpty else { return }

        // Avoid repeating the same clip twice running — repetition is what makes a
        // sound effect grating.
        var index = Int.random(in: 0..<clips.count)
        if clips.count > 1 && index == lastIndex {
            index = (index + 1) % clips.count
        }
        lastIndex = index

        guard let player = try? AVAudioPlayer(data: clips[index]) else { return }
        player.volume = 0.6
        player.prepareToPlay()
        player.play()

        // Hold a reference until it finishes, or ARC kills the sound mid-play.
        active.append(player)
        active.removeAll { !$0.isPlaying && $0.currentTime > 0 }
        if active.count > 8 { active.removeFirst(active.count - 8) }
    }
}
