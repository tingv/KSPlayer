import Foundation
@testable import KSPlayer
import Testing

@MainActor
final class KSAVPlayerTest {
    private var readyToPlayContinuation: CheckedContinuation<Void, Never>?
    private var bufferedCounts = [Int]()
    init() {}

    @Test
    func testPlayerLayer() async throws {
        let bundle = Bundle(for: Self.self)

        let testPaths = [
            ("h264", "MP4"),
            ("mjpeg", "flac"),
            ("hevc", "mkv"),
        ]

        for (name, ext) in testPaths {
            guard let path = bundle.path(forResource: name, ofType: ext) else {
                continue
            }
            await set(path: path)
        }
    }

    private func set(path: String) async {
        let url = URL(fileURLWithPath: path)
        let options = KSOptions()
        let player = KSAVPlayer(url: url, options: options)
        player.delegate = self
        player.prepareToPlay()
        // 等待 readyToPlay
        await withCheckedContinuation { continuation in
            readyToPlayContinuation = continuation
        }
        if player.isReadyToPlay {
            player.play()
        }
        player.stop()
    }
}

extension KSAVPlayerTest: MediaPlayerDelegate {
    func readyToPlay(player _: some MediaPlayerProtocol) {
        readyToPlayContinuation?.resume()
    }

    func changeLoadState(player _: some MediaPlayerProtocol) {}

    func changeBuffering(player _: some MediaPlayerProtocol, progress _: Int) {}

    func playBack(player _: some MediaPlayerProtocol, loopCount _: Int) {}

    func finish(player _: some MediaPlayerProtocol, error: Error?) {
        if error != nil {
            readyToPlayContinuation?.resume()
        }
    }
}
