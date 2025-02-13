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
    private var config = KSVideoPlayer.Coordinator()
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
    private var isDropdownShow = false
    private let liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)?
    public init(url: State<URL?>, options: State<KSOptions>, title: State<String>, subtitleDataSource: SubtitleDataSource?, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        _url = url
        _title = title
        _options = options
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
                    // 不要加这个，不然config无法释放，也可以在onDisappear调用removeMonitor释放
                    //                    #if os(macOS)
                    //                    NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
                    //                        isMaskShow = overView
                    //                        return $0
                    //                    }
                    //                    #endif
                }
                .onDisappear {
                    liftCycleBlock?(config, true)
                }
                .overlay {
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
                                isDropdownShow = true
                            default:
                                break
                            }
                        }
                    }
                    .focused($focusableView, equals: .play)
                    .opacity(!config.isMaskShow ? 1 : 0)
                    #endif
                    controllerView
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
                .sheet(isPresented: $isDropdownShow) {
                    VideoSettingView(config: config, subtitleTitle: title)
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
        if url.isAudio || url.isMovie {
            if let options {
                self.options = options
            }
            self.url = url
            title = url.lastPathComponent
        } else {
            let info = URLSubtitleInfo(url: url)
            config.playerLayer?.subtitleModel.selectedSubtitleInfo = info
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
    init(url: URL, options: KSOptions, title: String? = nil, subtitleDataSource: SubtitleDataSource? = nil, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        self.init(url: .init(wrappedValue: url), options: .init(wrappedValue: options), title: .init(wrappedValue: title ?? url.lastPathComponent), subtitleDataSource: subtitleDataSource, liftCycleBlock: liftCycleBlock)
    }

    init(playerLayer: KSPlayerLayer) {
        self.init(url: playerLayer.url, options: playerLayer.options)
        config.playerLayer = playerLayer
    }
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct VideoControllerView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @Binding
    fileprivate var title: String
    fileprivate let playerWidth: CGFloat
    @FocusState
    fileprivate var focusableView: KSVideoPlayerView.FocusableView?
    @State
    private var showVideoSetting = false
    @Environment(\.dismiss)
    private var dismiss
    init(config: KSVideoPlayer.Coordinator, title: Binding<String>, playerWidth: CGFloat, focusableView: FocusState<KSVideoPlayerView.FocusableView?>) {
        self.config = config
        _title = title
        self.playerWidth = playerWidth
        _focusableView = focusableView
    }

    public var body: some View {
        VStack {
            #if os(tvOS)
            Spacer()
            HStack(spacing: 24) {
                KSVideoPlayerViewBuilder.titleView(title: title, config: config)
                    .lineLimit(2)
                    .layoutPriority(100)
                KSVideoPlayerViewBuilder.muteButton(config: config)
                if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                    KSVideoPlayerViewBuilder.audioButton(config: config, audioTracks: audioTracks)
                }
                Spacer()
                    .layoutPriority(2)
                HStack(spacing: 24) {
                    KSVideoPlayerViewBuilder.playButton(config: config)
                    KSVideoPlayerViewBuilder.contentModeButton(config: config)
                    KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $config.playbackRate)
                    KSVideoPlayerViewBuilder.recordButton(config: config)
                    KSVideoPlayerViewBuilder.pipButton(config: config)
                    KSVideoPlayerViewBuilder.subtitleButton(config: config)
                    KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
                }
            }
            if config.isMaskShow {
                VideoTimeShowView(config: config, model: config.timemodel, timeFont: .caption2)
                    .focused($focusableView, equals: .slider)
            }
            #elseif os(macOS)
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    KSVideoPlayerViewBuilder.muteButton(config: config)
                    KSVideoPlayerViewBuilder.volumeSlider(config: config, volume: $config.playbackVolume)
                        .frame(maxWidth: 100)
                    if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                        KSVideoPlayerViewBuilder.audioButton(config: config, audioTracks: audioTracks)
                    }
                    Spacer()
                    KSVideoPlayerViewBuilder.backwardButton(config: config)
                        .font(.largeTitle)
                    KSVideoPlayerViewBuilder.playButton(config: config)
                        .font(.largeTitle)
                    KSVideoPlayerViewBuilder.forwardButton(config: config)
                        .font(.largeTitle)
                    Spacer()
                    KSVideoPlayerViewBuilder.contentModeButton(config: config)
                    KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $config.playbackRate)
                    KSVideoPlayerViewBuilder.recordButton(config: config)
                    KSVideoPlayerViewBuilder.subtitleButton(config: config)
                    KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
                }
                // 设置opacity为0，还是会去更新View。所以只能这样了
                if config.isMaskShow {
                    VideoTimeShowView(config: config, model: config.timemodel, timeFont: .caption2)
                }
            }
            .padding()
            .background(.black.opacity(0.35))
            .cornerRadius(10)
            .padding(.horizontal, playerWidth * 0.15)
            .padding(.vertical, 24)
            #else
            HStack {
                Button {
                    dismiss()
                    #if os(iOS)
                    KSOptions.supportedInterfaceOrientations = nil
                    #endif
                } label: {
                    Image(systemName: "x.circle.fill")
                }
                #if os(xrOS)
                .glassBackgroundEffect()
                #endif
                KSVideoPlayerViewBuilder.muteButton(config: config)
                KSVideoPlayerViewBuilder.volumeSlider(config: config, volume: $config.playbackVolume)
                    .frame(maxWidth: 100)
                    .tint(.white.opacity(0.8))
                    .padding(.leading, 16)
                #if os(xrOS)
                    .glassBackgroundEffect()
                #endif
                if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                    KSVideoPlayerViewBuilder.audioButton(config: config, audioTracks: audioTracks)
                    #if os(xrOS)
                        .aspectRatio(1, contentMode: .fit)
                        .glassBackgroundEffect()
                    #endif
                }
                Spacer()
                #if os(iOS)
                if config.playerLayer?.player.allowsExternalPlayback == true {
                    AirPlayView().fixedSize()
                }
                KSVideoPlayerViewBuilder.contentModeButton(config: config)
                if config.playerLayer?.player.naturalSize.isHorizonal == true {
                    KSVideoPlayerViewBuilder.landscapeButton
                }
                #endif
            }
            Spacer()
            #if !os(xrOS)
            HStack(spacing: 20) {
                KSVideoPlayerViewBuilder.backwardButton(config: config)
                KSVideoPlayerViewBuilder.playButton(config: config)
                KSVideoPlayerViewBuilder.forwardButton(config: config)
            }
            Spacer()
            HStack(spacing: 18) {
                KSVideoPlayerViewBuilder.titleView(title: title, config: config)
                Spacer(minLength: 0)
                KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $config.playbackRate)
                KSVideoPlayerViewBuilder.pipButton(config: config)
                KSVideoPlayerViewBuilder.recordButton(config: config)
                KSVideoPlayerViewBuilder.subtitleButton(config: config)
                KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
            }
            if config.isMaskShow {
                VideoTimeShowView(config: config, model: config.timemodel, timeFont: .caption2)
            }
            #endif
            #endif
        }
        .sheet(isPresented: $showVideoSetting) {
            VideoSettingView(config: config, subtitleTitle: title)
        }
        #if os(xrOS)
        .ornament(visibility: config.isMaskShow ? .visible : .hidden, attachmentAnchor: .scene(.bottom)) {
            VStack(alignment: .leading) {
                HStack {
                    KSVideoPlayerViewBuilder.titleView(title: title, config: config)
                }
                HStack(spacing: 16) {
                    KSVideoPlayerViewBuilder.backwardButton(config: config)
                    KSVideoPlayerViewBuilder.playButton(config: config)
                    KSVideoPlayerViewBuilder.forwardButton(config: config)
                    VideoTimeShowView(config: config, model: config.timemodel, timeFont: .title3)
                    KSVideoPlayerViewBuilder.contentModeButton(config: config)
                    KSVideoPlayerViewBuilder.subtitleButton(config: config)
                    KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $config.playbackRate)
                    KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
                }
            }
            .frame(minWidth: playerWidth / 1.5)
            .buttonStyle(.plain)
            .padding(.vertical, 24)
            .padding(.horizontal, 36)
            .glassBackgroundEffect()
        }
        #endif
        #if os(tvOS)
        .padding(.horizontal, 80)
        .padding(.bottom, 80)
        .background(LinearGradient(
            stops: [
                Gradient.Stop(color: .black.opacity(0), location: 0.22),
                Gradient.Stop(color: .black.opacity(0.7), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        ))
        #else
            .font(.title)
            .buttonStyle(.borderless)
            .padding()
        #if os(iOS)
            .background {
                Color.black.opacity(0.35).ignoresSafeArea()
            }
        #endif
        #endif
    }
}

@available(iOS 15, tvOS 15, macOS 12, *)
struct VideoTimeShowView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var model: ControllerTimeModel
    fileprivate var timeFont: Font
    public var body: some View {
        if let playerLayer = config.playerLayer, playerLayer.player.seekable {
            HStack {
                Text(model.currentTime.toString(for: .minOrHour))
                    .font(timeFont.monospacedDigit())
                PlayerSlider(model: model, bufferValue: Float(playerLayer.player.playableTime)) { onEditingChanged in
                    if onEditingChanged {
                        playerLayer.pause()
                    } else {
                        config.seek(time: TimeInterval(model.currentTime))
                    }
                }
                .frame(maxHeight: 20)
                #if os(xrOS)
                    .tint(.white.opacity(0.8))
                #endif
                Text((model.totalTime).toString(for: .minOrHour))
                    .font(timeFont.monospacedDigit())
            }
            .font(.system(.title2))
        } else {
            Text("Live Streaming".localized)
        }
    }
}

@available(iOS 16, macOS 13, tvOS 16, *)
struct VideoSettingView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @State
    fileprivate var subtitleTitle: String
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        PlatformView {
            if let playerLayer = config.playerLayer {
                let videoTracks = playerLayer.player.tracks(mediaType: .video)
                if !videoTracks.isEmpty {
                    Picker(selection: Binding {
                        videoTracks.first { $0.isEnabled }?.trackID
                    } set: { value in
                        if let track = videoTracks.first(where: { $0.trackID == value }) {
                            playerLayer.player.select(track: track)
                        }
                    }) {
                        ForEach(videoTracks, id: \.trackID) { track in
                            Text(track.description).tag(track.trackID as Int32?)
                        }
                    } label: {
                        Label("Video Track".localized, systemImage: "video.fill")
                    }

                    Picker("Video Display Type".localized, selection: Binding {
                        if playerLayer.options.display === KSOptions.displayEnumVR {
                            return "VR"
                        } else if playerLayer.options.display === KSOptions.displayEnumVRBox {
                            return "VRBox"
                        } else {
                            return "Plane"
                        }
                    } set: { value in
                        if value == "VR" {
                            playerLayer.options.display = KSOptions.displayEnumVR
                        } else if value == "VRBox" {
                            playerLayer.options.display = KSOptions.displayEnumVRBox
                        } else {
                            playerLayer.options.display = KSOptions.displayEnumPlane
                        }
                    }) {
                        Text("Plane").tag("Plane")
                        Text("VR").tag("VR")
                        Text("VRBox").tag("VRBox")
                    }
                    LabeledContent("Video Type".localized, value: (videoTracks.first { $0.isEnabled }?.dynamicRange ?? .sdr).description)
                    LabeledContent("Stream Type".localized, value: (videoTracks.first { $0.isEnabled }?.fieldOrder ?? .progressive).description)
                    LabeledContent("Decode Type".localized, value: playerLayer.options.decodeType.rawValue)
                }
                TextField("Subtitle delay".localized, value: Binding {
                    playerLayer.subtitleModel.subtitleDelay
                } set: { value in
                    playerLayer.subtitleModel.subtitleDelay = value
                }, format: .number)
                TextField("Title".localized, text: $subtitleTitle)
                Button("Search Subtitle".localized) {
                    playerLayer.subtitleModel.searchSubtitle(query: subtitleTitle, languages: [Locale.current.identifier])
                }
                .buttonStyle(.bordered)

                if let dynamicInfo = playerLayer.player.dynamicInfo {
                    DynamicInfoView(dynamicInfo: dynamicInfo)
                }
                let fileSize = playerLayer.player.fileSize
                if fileSize > 0 {
                    LabeledContent("File Size".localized, value: fileSize.kmFormatted + "B")
                }
            } else {
                Text("Loading...".localized)
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst) || os(xrOS)
        .toolbar {
            Button("Done".localized) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        #endif
    }
}

@available(iOS 16, macOS 13, tvOS 16, *)
public struct DynamicInfoView: View {
    @ObservedObject
    fileprivate var dynamicInfo: DynamicInfo
    public var body: some View {
        LabeledContent("Display FPS".localized, value: dynamicInfo.displayFPS, format: .number)
        LabeledContent("Audio Video sync".localized, value: dynamicInfo.audioVideoSyncDiff, format: .number)
        LabeledContent("Dropped Frames".localized, value: dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount, format: .number)
        LabeledContent("Bytes Read".localized, value: dynamicInfo.bytesRead.kmFormatted + "B")
        LabeledContent("Audio bitrate".localized, value: dynamicInfo.audioBitrate.kmFormatted + "bps")
        LabeledContent("Video bitrate".localized, value: dynamicInfo.videoBitrate.kmFormatted + "bps")
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
