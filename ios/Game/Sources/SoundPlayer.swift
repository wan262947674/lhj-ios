import AVFoundation

final class SoundPlayer {

    static let shared = SoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]
    var enabled = true

    private init() {}

    func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func play(_ name: String, loop: Bool = false) {
        guard enabled else { return }
        if let player = players[name] {
            player.numberOfLoops = loop ? -1 : 0
            player.currentTime = 0
            player.play()
            return
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = loop ? -1 : 0
        player.prepareToPlay()
        players[name] = player
        player.play()
    }

    func stop(_ name: String) {
        players[name]?.stop()
        players[name]?.currentTime = 0
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
    }
}
