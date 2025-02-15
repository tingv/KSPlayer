import Foundation
@testable import KSPlayer
import Testing

@MainActor
final class KSPlayerLayerTest {
    private var readyToPlayContinuation: CheckedContinuation<Void, Never>?
    private var bufferedCounts = [Int]()
    init() {
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.isSecondOpen = true
        KSOptions.isAccurateSeek = true
    }

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

        let playerLayer = KSPlayerLayer(url: url, options: options)
        playerLayer.delegate = self

        // 验证初始状态
        #expect(playerLayer.state == .preparing)

        // 等待 readyToPlay
        await withCheckedContinuation { continuation in
            readyToPlayContinuation = continuation
        }

        // 验证准备就绪状态
        #expect(playerLayer.player.isReadyToPlay == true)
        #expect(playerLayer.state == .readyToPlay)

        // 测试播放控制
        playerLayer.play()
        playerLayer.pause()
        #expect(playerLayer.state == .paused)
        var seekContinuation: CheckedContinuation<Void, Never>?
        playerLayer.seek(time: 2, autoPlay: true) { _ in
            seekContinuation?.resume()
        }
        #expect(playerLayer.state == .buffering)
        // 测试 seek 操作
        await withCheckedContinuation { continuation in
            seekContinuation = continuation
        }
        // 验证结束状态
        playerLayer.finish(player: playerLayer.player, error: nil)
        #expect(playerLayer.state == .playedToTheEnd)

        // 测试停止
        playerLayer.stop()
        #expect(playerLayer.state == .initialized)

        // 验证缓冲区
        #expect(bufferedCounts.allSatisfy { $0 <= 0 })
    }
}

extension KSPlayerLayerTest: KSPlayerLayerDelegate {
    func player(layer _: KSPlayerLayer, state: KSPlayerState) {
        if state == .readyToPlay {
            readyToPlayContinuation?.resume()
        }
    }

    func player(layer _: KSPlayerLayer, currentTime _: TimeInterval, totalTime _: TimeInterval) {}

    func player(layer _: KSPlayerLayer, finish _: (any Error)?) {}

    func player(layer _: KSPlayerLayer, bufferedCount: Int, consumeTime _: TimeInterval) {
        bufferedCounts.append(bufferedCount)
    }
}
