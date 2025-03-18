//
//  File.swift
//  KSPlayer
//
//  Created by kintan on 2022/1/29.
//
import AVFoundation
import MediaPlayer
import SwiftUI

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
@MainActor
public struct KSVideoPlayerView: View {
    private let subtitleDataSource: SubtitleDataSource?
    @State
    public var options: KSOptions
    @State
    private var title: String
    @StateObject
    private var config: KSVideoPlayer.Coordinator
    @State
    public var url: URL? {
        didSet {
            #if os(macOS)
            if let url {
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            }
            #endif
        }
    }

    @Environment(\.dismiss)
    private var dismiss
    @FocusState
    private var focusableView: FocusableView?
    @State
    private var showVideoSetting = false
    private let liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)?
    public init(coordinator: KSVideoPlayer.Coordinator? = nil, url: State<URL?>, options: State<KSOptions>, title: State<String>, subtitleDataSource: SubtitleDataSource?, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        _url = url
        _title = title
        _options = options
        _config = .init(wrappedValue: coordinator ?? KSVideoPlayer.Coordinator())
        self.subtitleDataSource = subtitleDataSource
        self.liftCycleBlock = liftCycleBlock
        #if os(macOS)
        if let url = url.wrappedValue {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
        #endif
    }

    public var body: some View {
        if let url {
            KSCorePlayerView(config: .init(initialValue: config), url: url, options: options, title: _title, subtitleDataSource: subtitleDataSource)
                .onAppear {
                    liftCycleBlock?(config, false)
                }
                .onDisappear {
                    liftCycleBlock?(config, true)
                }
                .overlay {
                    // 需要放在这里才能生效
                    #if canImport(UIKit)
                    GestureView { direction in
                        switch direction {
                        case .left:
                            config.skip(interval: -15)
                        case .right:
                            config.skip(interval: 15)
                        default:
                            config.isMaskShow = true
                        }
                    } pressAction: { direction in
                        if !config.isMaskShow {
                            switch direction {
                            case .left:
                                config.skip(interval: -15)
                            case .right:
                                config.skip(interval: 15)
                            case .up:
                                config.mask(show: true, autoHide: false)
                            case .down:
                                showVideoSetting = true
                            default:
                                break
                            }
                        }
                    }
                    .focused($focusableView, equals: .play)
                    .opacity(!config.isMaskShow ? 1 : 0)
                    #endif
                    controllerView
                        .sheet(isPresented: $showVideoSetting) {
                            VideoSettingView(config: config, subtitleTitle: title)
                        }
                }
                // 要放在这里才可以生效
                .onTapGesture {
                    config.isMaskShow.toggle()
                }
                .preferredColorScheme(.dark)
                .tint(.white)
                .persistentSystemOverlays(.hidden)
                .toolbar(.hidden, for: .automatic)
            #if !os(macOS)
                .toolbar(.hidden, for: .tabBar)
            #endif
                .focusedObject(config)
                .onChange(of: config.isMaskShow) { newValue in
                    if newValue {
                        focusableView = .slider
                    } else {
                        focusableView = .play
                    }
                }
            #if os(tvOS)
                // 要放在最上层才不会有焦点丢失问题
                .onPlayPauseCommand {
                    if config.state.isPlaying {
                        config.playerLayer?.pause()
                    } else {
                        config.playerLayer?.play()
                    }
                }
                .onExitCommand {
                    if config.isMaskShow {
                        config.isMaskShow = false
                    } else {
                        switch focusableView {
                        case .play:
                            dismiss()
                        default:
                            focusableView = .play
                        }
                    }
                }
            #endif
            #if !os(tvOS)
            // 要放在最上面的view。这样才不会被controllerView盖住
                .onHover { new in
                config.isMaskShow = new
            }
            #endif
        } else {
            controllerView
        }
    }

    @MainActor
    public func openURL(_ url: URL, options: KSOptions? = nil) {
        if url.isSubtitle {
            let info = URLSubtitleInfo(url: url)
            config.playerLayer?.subtitleModel.selectedSubtitleInfo = info
        } else {
            if let options {
                self.options = options
            }
            self.url = url
            title = url.lastPathComponent
        }
    }

    private var controllerView: some View {
        VideoControllerView(config: config, title: $title, playerWidth: config.playerLayer?.player.view.frame.width ?? 0, focusableView: _focusableView)
            .focused($focusableView, equals: .controller)
            .opacity(config.isMaskShow ? 1 : 0)
        #if os(tvOS)
            .ignoresSafeArea()
        #endif
        #if !os(tvOS)
        // 要放在最上面才能修改url
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers -> Bool in
            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                if let data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) {
                    Task { @MainActor in
                        openURL(url)
                    }
                }
            }
            return true
        }
        #endif
    }

    enum FocusableView {
        case play, controller, slider
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public extension KSVideoPlayerView {
    init(url: URL, options: KSOptions, title: String? = nil, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        self.init(url: url, options: options, title: title, subtitleDataSource: nil, liftCycleBlock: liftCycleBlock)
    }

    // xcode 15.2还不支持对MainActor参数设置默认值
    init(coordinator: KSVideoPlayer.Coordinator? = nil, url: URL, options: KSOptions, title: String? = nil, subtitleDataSource: SubtitleDataSource? = nil, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        self.init(coordinator: coordinator, url: .init(wrappedValue: url), options: .init(wrappedValue: options), title: .init(wrappedValue: title ?? url.lastPathComponent), subtitleDataSource: subtitleDataSource, liftCycleBlock: liftCycleBlock)
    }

    init(playerLayer: KSPlayerLayer) {
        let coordinator = KSVideoPlayer.Coordinator(playerLayer: playerLayer)
        self.init(coordinator: coordinator, url: playerLayer.url, options: playerLayer.options)
    }
}

#if DEBUG
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct KSVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "https://raw.githubusercontent.com/kingslay/TestVideo/main/subrip.mkv")!
        KSVideoPlayerView(url: url, options: KSOptions())
    }
}

// struct AVContentView: View {
//    var body: some View {
//        StructAVPlayerView().frame(width: UIScene.main.bounds.width, height: 400, alignment: .center)
//    }
// }
//
// struct StructAVPlayerView: UIViewRepresentable {
//    let playerVC = AVPlayerViewController()
//    typealias UIViewType = UIView
//    func makeUIView(context _: Context) -> UIView {
//        playerVC.view
//    }
//
//    func updateUIView(_: UIView, context _: Context) {
//        playerVC.player = AVPlayer(url: URL(string: "https://bitmovin-a.akamaihd.net/content/dataset/multi-codec/hevc/stream_fmp4.m3u8")!)
//    }
// }
#endif
