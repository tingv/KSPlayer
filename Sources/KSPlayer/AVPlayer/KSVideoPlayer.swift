//
//  KSVideoPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2023/2/11.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit

public typealias UIHostingController = NSHostingController
public typealias UIViewRepresentable = NSViewRepresentable
#endif

@MainActor
public struct KSVideoPlayer {
    @ObservedObject
    public var coordinator: Coordinator
    public let url: URL
    public let options: KSOptions
    public init(coordinator: ObservedObject<Coordinator>, url: URL, options: KSOptions) {
        _coordinator = coordinator
        self.url = url
        self.options = options
    }

    public init(playerLayer: KSPlayerLayer) {
        self.init(coordinator: .init(wrappedValue: Coordinator(playerLayer: playerLayer)), url: playerLayer.url, options: playerLayer.options)
    }

    public init?(coordinator: Coordinator) {
        if let playerLayer = coordinator.playerLayer {
            self.init(playerLayer: playerLayer)
        } else {
            return nil
        }
    }
}

extension KSVideoPlayer: UIViewRepresentable {
    public func makeCoordinator() -> Coordinator {
        coordinator
    }

    #if canImport(UIKit)
    public typealias UIViewType = UIView
    public func makeUIView(context: Context) -> UIViewType {
        context.coordinator.makeView(url: url, options: options)
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        updateView(view, context: context)
    }

    // iOS tvOS真机先调用onDisappear在调用dismantleUIView，但是模拟器就反过来了。
    public static func dismantleUIView(_: UIViewType, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }

    #else
    public typealias NSViewType = UIView
    public func makeNSView(context: Context) -> NSViewType {
        context.coordinator.makeView(url: url, options: options)
    }

    public func updateNSView(_ view: NSViewType, context: Context) {
        updateView(view, context: context)
    }

    // macOS先调用onDisappear在调用dismantleNSView
    public static func dismantleNSView(_ view: NSViewType, coordinator: Coordinator) {
        coordinator.resetPlayer()
        view.window?.aspectRatio = CGSize(width: 16, height: 9)
    }
    #endif

    @MainActor
    private func updateView(_: UIView, context: Context) {
        if context.coordinator.playerLayer?.url != url {
            _ = context.coordinator.makeView(url: url, options: options)
        }
    }

    @MainActor
    public final class Coordinator: ObservableObject {
        @Published
        public var state: KSPlayerState = .initialized

        @Published
        public var isMuted: Bool = false {
            didSet {
                playerLayer?.player.isMuted = isMuted
            }
        }

        @Published
        public var playbackVolume: Float = 1.0 {
            didSet {
                playerLayer?.player.playbackVolume = playbackVolume
            }
        }

        @Published
        public var isScaleAspectFill = false {
            didSet {
                playerLayer?.player.contentMode = isScaleAspectFill ? .scaleAspectFill : .scaleAspectFit
            }
        }

        @Published
        public var isRecord = false {
            didSet {
                if isRecord != oldValue {
                    if isRecord {
                        if let url = KSOptions.recordDir {
                            if !FileManager.default.fileExists(atPath: url.path) {
                                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            }
                            if FileManager.default.fileExists(atPath: url.path) {
                                playerLayer?.player.startRecord(url: url.appendingPathComponent("\(Date().description).mov"))
                            }
                        }
                    } else {
                        playerLayer?.player.stopRecord()
                    }
                }
            }
        }

        @Published
        public var playbackRate: Float = 1.0 {
            didSet {
                playerLayer?.player.playbackRate = playbackRate
            }
        }

        @Published
        @MainActor
        public var isMaskShow = true {
            didSet {
                if isMaskShow != oldValue {
                    mask(show: isMaskShow)
                }
            }
        }

        public var timemodel = ControllerTimeModel()
        // 在SplitView模式下，第二次进入会先调用makeUIView。然后在调用之前的dismantleUIView.所以如果进入的是同一个View的话，就会导致playerLayer被清空了。最准确的方式是在onDisappear清空playerLayer
        public private(set) var playerLayer: KSPlayerLayer? {
            didSet {
                guard let oldValue else {
                    return
                }
                // 进入pip一定要清空translationSession。不然会crash
                #if (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
                if #available(iOS 18.0, macOS 15.0, *) {
                    oldValue.subtitleModel.translationSessionConf?.invalidate()
                    oldValue.subtitleModel.translationSession = nil
                }
                #endif
                if !oldValue.isPictureInPictureActive {
                    // 需要清空delegate，不然会更新state。然后crash
                    oldValue.delegate = nil
                    oldValue.stop()
                }
            }
        }

        private var delayHide: DispatchWorkItem?
        #if os(macOS)
        private var eventMonitor: Any? {
            willSet {
                if let eventMonitor {
                    NSEvent.removeMonitor(eventMonitor)
                }
            }
        }
        #endif
        public var onPlay: ((TimeInterval, TimeInterval) -> Void)?
        public var onFinish: ((KSPlayerLayer, Error?) -> Void)?
        public var onStateChanged: ((KSPlayerLayer, KSPlayerState) -> Void)?
        public var onBufferChanged: ((Int, TimeInterval) -> Void)?

        public init(playerLayer: KSPlayerLayer) {
            self.playerLayer = playerLayer
            playerLayer.delegate = self
            state = playerLayer.state
        }

        public init() {}

        public func makeView(url: URL, options: KSOptions) -> UIView {
            #if os(macOS)
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] in
                guard let self else { return nil }
                if let view = playerLayer?.player.view, view.window == $0.window {
                    let mouseLocation = $0.locationInWindow
                    isMaskShow = view.bounds.contains(mouseLocation)
                }
                return $0
            }
            #endif
            if let playerLayer {
                if playerLayer.url == url {
                    playerLayer.delegate = self
                    return playerLayer.player.view
                }
                playerLayer.delegate = nil
                playerLayer.set(url: url, options: options)
                playerLayer.delegate = self
                return playerLayer.player.view
            } else {
                let playerLayer = KSComplexPlayerLayer(url: url, options: options, delegate: self)
                self.playerLayer = playerLayer
                return playerLayer.player.view
            }
        }

        public func resetPlayer() {
            #if os(macOS)
            eventMonitor = nil
            #endif
            onStateChanged = nil
            onPlay = nil
            onFinish = nil
            onBufferChanged = nil
            playerLayer = nil
            delayHide?.cancel()
            delayHide = nil
        }

        public func skip(interval: Int) {
            if let playerLayer {
                seek(time: playerLayer.player.currentPlaybackTime + TimeInterval(interval))
            }
        }

        public func seek(time: TimeInterval) {
            playerLayer?.seek(time: TimeInterval(time))
        }

        @MainActor
        public func mask(show: Bool, autoHide: Bool = true) {
            isMaskShow = show
            if show {
                delayHide?.cancel()
                // 播放的时候才自动隐藏
                if state == .bufferFinished, autoHide {
                    delayHide = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        if state == .bufferFinished {
                            isMaskShow = false
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + KSOptions.animateDelayTimeInterval,
                                                  execute: delayHide!)
                }
            }
            #if os(macOS)
            show ? NSCursor.unhide() : NSCursor.setHiddenUntilMouseMoves(true)
            if let view = playerLayer?.player.view, let window = view.window, !window.styleMask.contains(.fullScreen), let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview {
                if show {
                    titlebarContainer.isHidden = false
                } else {
                    // 因为光标处于状态栏的时候，onHover就会返回false了，所以要自己计算
                    let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
                    if !view.frame.contains(point) {
                        // 需要异步执行不然macOS15无法隐藏
                        DispatchQueue.main.async {
                            titlebarContainer.isHidden = true
                        }
                    }
                }
            }
            #endif
        }
    }
}

extension KSVideoPlayer.Coordinator: KSPlayerLayerDelegate {
    public func player(layer: KSPlayerLayer, state: KSPlayerState) {
        self.state = state
        onStateChanged?(layer, state)
        if state == .readyToPlay {
            playbackRate = layer.player.playbackRate
            #if DEBUG
            timemodel.preLoadProtocol = layer.player.ioContext as? any PreLoadProtocol
            #endif
        } else if state == .bufferFinished {
            isMaskShow = false
        } else {
            if state != .preparing, !isMaskShow {
                isMaskShow = true
            }
        }
    }

    public func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        onPlay?(currentTime, totalTime)
        guard var current = Int(exactly: ceil(currentTime)), var total = Int(exactly: ceil(totalTime)), var playable = Int(exactly: ceil(layer.player.playableTime)) else {
            return
        }
        if layer.state.isPlaying {
            current = max(0, current)
            total = max(0, total)
            if timemodel.currentTime != current {
                timemodel.currentTime = current
            }
            if total == 0 {
                timemodel.totalTime = timemodel.currentTime
            } else {
                if timemodel.totalTime != total {
                    timemodel.totalTime = total
                }
            }
        }
        playable = max(0, playable)
        if timemodel.bufferTime != playable {
            timemodel.bufferTime = playable
        }
    }

    public func player(layer: KSPlayerLayer, finish error: Error?) {
        onFinish?(layer, error)
    }

    public func player(layer _: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        onBufferChanged?(bufferedCount, consumeTime)
    }

    public func playerDidClear(layer _: KSPlayerLayer) {}
}

extension KSVideoPlayer: @preconcurrency Equatable {
    @MainActor
    public static func == (lhs: KSVideoPlayer, rhs: KSVideoPlayer) -> Bool {
        lhs.url == rhs.url
    }
}

@MainActor
public extension KSVideoPlayer {
    func onBufferChanged(_ handler: @escaping (Int, TimeInterval) -> Void) -> Self {
        coordinator.onBufferChanged = handler
        return self
    }

    /// Playing to the end.
    func onFinish(_ handler: @escaping (KSPlayerLayer, Error?) -> Void) -> Self {
        coordinator.onFinish = handler
        return self
    }

    func onPlay(_ handler: @escaping (TimeInterval, TimeInterval) -> Void) -> Self {
        coordinator.onPlay = handler
        return self
    }

    /// Playback status changes, such as from play to pause.
    func onStateChanged(_ handler: @escaping (KSPlayerLayer, KSPlayerState) -> Void) -> Self {
        coordinator.onStateChanged = handler
        return self
    }
}

#if (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
import Translation

public extension KSVideoPlayer {
    @MainActor
    func translationView() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            return translationTask(coordinator.playerLayer?.subtitleModel.translationSessionConf) { session in
                do {
                    try await session.prepareTranslation()
                    coordinator.playerLayer?.subtitleModel.translationSession = session
                } catch {
                    KSLog(error)
                }
            }
        } else {
            return self
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
extension TranslationSession: @unchecked Sendable {}
#endif

/// 这是一个频繁变化的model。View要少用这个
public class ControllerTimeModel: ObservableObject {
    // 改成int才不会频繁更新
    @Published
    public var currentTime = 0
    @Published
    public var totalTime = 1
    @Published
    public var bufferTime = 0
    #if DEBUG
    public var preLoadProtocol: PreLoadProtocol?
    #endif
}

#if DEBUG
struct KSVideoPlayer_Previews: PreviewProvider {
    static var previews: some View {
        KSOptions.firstPlayerType = KSMEPlayer.self
        let url = URL(string: "https://raw.githubusercontent.com/kingslay/TestVideo/main/h264.mp4")!
        let coordinator = KSVideoPlayer.Coordinator()
        return KSVideoPlayer(coordinator: .init(initialValue: coordinator), url: url, options: KSOptions())
    }
}
#endif
