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
    private let subtitleDataSouce: SubtitleDataSouce?
    public let options: KSOptions
    @State
    private var title: String
    @StateObject
    private var config: KSVideoPlayer.Coordinator
    @State
    public var url: URL
    @Environment(\.dismiss)
    private var dismiss
    @FocusState
    private var focusableView: FocusableView?
    @State
    private var isDropdownShow = false
    public init(url: URL, options: KSOptions, title: String? = nil) {
        self.init(coordinator: KSVideoPlayer.Coordinator(), url: url, options: options, title: title, subtitleDataSouce: nil)
    }

    // xcode 15.2还不支持对MainActor参数设置默认值
    public init(coordinator: KSVideoPlayer.Coordinator, url: URL, options: KSOptions, title: String? = nil, subtitleDataSouce: SubtitleDataSouce? = nil) {
        self.init(coordinator: coordinator, url: .init(wrappedValue: url), options: options, title: .init(wrappedValue: title ?? url.lastPathComponent), subtitleDataSouce: subtitleDataSouce)
    }

    public init(coordinator: KSVideoPlayer.Coordinator, url: State<URL>, options: KSOptions, title: State<String>, subtitleDataSouce: SubtitleDataSouce?) {
        _url = url
        _config = .init(wrappedValue: coordinator)
        _title = title
        #if os(macOS)
        NSDocumentController.shared.noteNewRecentDocumentURL(url.wrappedValue)
        #endif
        self.options = options
        self.subtitleDataSouce = subtitleDataSouce
    }

    public var body: some View {
        KSCorePlayerView(config: config, url: _url, options: options, title: _title, subtitleDataSouce: subtitleDataSouce)
            .onAppear {
                focusableView = .play
                // 不要加这个，不然config无法释放，也可以在onDisappear调用removeMonitor释放
                //                    #if os(macOS)
                //                    NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
                //                        isMaskShow = overView
                //                        return $0
                //                    }
                //                    #endif
            }
            .overlay {
                controllerView
            }
            .preferredColorScheme(.dark)
            .tint(.white)
            .persistentSystemOverlays(.hidden)
            .toolbar(.hidden, for: .automatic)
            .focusedObject(config)
            .onChange(of: config.isMaskShow) { newValue in
                if newValue {
                    focusableView = .controller
                } else {
                    focusableView = .play
                }
            }
            .onChange(of: isDropdownShow) { newValue in
                if newValue {
                    focusableView = .info
                } else {
                    focusableView = .play
                }
            }
        #if !os(iOS)
            .focused($focusableView, equals: .play)
        #endif
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
        .onMoveCommand { direction in
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
                @unknown default:
                    break
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
    }

    private var controllerView: some View {
        VideoControllerView(config: config, title: $title, playerWidth: config.playerLayer?.player.view?.frame.width ?? 0, focusableView: $focusableView)
            .focused($focusableView, equals: .controller)
            .opacity(config.isMaskShow ? 1 : 0)
        #if os(tvOS)
            .ignoresSafeArea()
        #endif
    }

    fileprivate enum FocusableView {
        case play, controller, info
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public struct KSCorePlayerView: View {
    @StateObject
    private var config: KSVideoPlayer.Coordinator
    @State
    public var url: URL {
        didSet {
            #if os(macOS)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            #endif
        }
    }

    public let options: KSOptions
    @State
    private var title: String
    private let subtitleDataSouce: SubtitleDataSouce?
    public init(config: KSVideoPlayer.Coordinator, url: State<URL>, options: KSOptions, title: State<String>, subtitleDataSouce: SubtitleDataSouce?) {
        _config = .init(wrappedValue: config)
        _url = url
        self.options = options
        _title = title
        self.subtitleDataSouce = subtitleDataSouce
    }

    public var body: some View {
        KSVideoPlayer(coordinator: config, url: url, options: options)
            .onStateChanged { playerLayer, state in
                if state == .readyToPlay {
                    if let subtitleDataSouce {
                        config.playerLayer?.subtitleModel.addSubtitle(dataSouce: subtitleDataSouce)
                    }
                    if let movieTitle = playerLayer.player.dynamicInfo?.metadata["title"] {
                        title = movieTitle
                    }
                }
            }
            .onBufferChanged { bufferedCount, consumeTime in
                KSLog("bufferedCount \(bufferedCount), consumeTime \(consumeTime)")
            }
        #if canImport(UIKit)
            .onSwipe { _ in
                config.isMaskShow = true
            }
        #endif
            .ignoresSafeArea()

        #if os(iOS) || os(xrOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(iOS)
        .focusable(!config.isMaskShow)
        #endif
        #if !os(xrOS)
        .onKeyPressLeftArrow {
            config.skip(interval: -15)
        }
        .onKeyPressRightArrow {
            config.skip(interval: 15)
        }
        .onKeyPressSapce {
            if config.state.isPlaying {
                config.playerLayer?.pause()
            } else {
                config.playerLayer?.play()
            }
        }
        #endif
        #if os(macOS)
        .navigationTitle(title)
        .onTapGesture(count: 2) {
            guard let view = config.playerLayer?.player.view else {
                return
            }
            view.window?.toggleFullScreen(nil)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
        }
        .onExitCommand {
            config.playerLayer?.player.view?.exitFullScreenMode()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                config.skip(interval: -15)
            case .right:
                config.skip(interval: 15)
            case .up:
                config.playerLayer?.player.playbackVolume += 0.2
            case .down:
                config.playerLayer?.player.playbackVolume -= 0.2
            @unknown default:
                break
            }
        }
        #endif
        .onTapGesture {
            config.isMaskShow.toggle()
        }
        #if !os(tvOS)
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers -> Bool in
            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                if let data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) {
                    openURL(url)
                }
            }
            return true
        }
        #endif
    }

    public func openURL(_ url: URL) {
        runOnMainThread {
            if url.isAudio || url.isMovie {
                self.url = url
                title = url.lastPathComponent
            } else {
                let info = URLSubtitleInfo(url: url)
                config.playerLayer?.subtitleModel.selectedSubtitleInfo = info
            }
        }
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
struct VideoControllerView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @Binding
    fileprivate var title: String
    fileprivate let playerWidth: CGFloat
    @FocusState.Binding
    fileprivate var focusableView: KSVideoPlayerView.FocusableView?
    @State
    private var showVideoSetting = false
    @Environment(\.dismiss)
    private var dismiss
    public var body: some View {
        VStack {
            #if os(tvOS)
            Spacer()
            HStack(spacing: 10) {
                KSVideoPlayerViewBuilder.titleView(title: title, config: config)
                    .lineLimit(2)
                    .layoutPriority(100)
                KSVideoPlayerViewBuilder.muteButton(config: config)
                if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                    audioButton(audioTracks: audioTracks)
                }
                Spacer()
                    .layoutPriority(2)
                HStack(spacing: 10) {
                    KSVideoPlayerViewBuilder.playButton(config: config)
                    contentModeButton
                    playbackRateButton
                    KSVideoPlayerViewBuilder.recordButton(config: config)
                    pipButton
                    subtitleButton
                    infoButton
                }
                .font(.caption)
            }
            if config.isMaskShow {
                VideoTimeShowView(config: config, model: config.timemodel, timeFont: .caption2)
            }
            #elseif os(macOS)
            Spacer()
            VStack(spacing: 10) {
                HStack {
                    KSVideoPlayerViewBuilder.muteButton(config: config)
                    volumeSlider
                        .frame(maxWidth: 100)
                    if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                        audioButton(audioTracks: audioTracks)
                    }
                    Spacer()
                    KSVideoPlayerViewBuilder.backwardButton(config: config)
                        .font(.largeTitle)
                    KSVideoPlayerViewBuilder.playButton(config: config)
                        .font(.largeTitle)
                    KSVideoPlayerViewBuilder.forwardButton(config: config)
                        .font(.largeTitle)
                    Spacer()
                    contentModeButton
                    playbackRateButton
                    KSVideoPlayerViewBuilder.recordButton(config: config)
                    subtitleButton
                    infoButton
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
                } label: {
                    Image(systemName: "x.circle.fill")
                }
                #if os(xrOS)
                .glassBackgroundEffect()
                #endif
                KSVideoPlayerViewBuilder.muteButton(config: config)
                volumeSlider
                    .frame(maxWidth: 100)
                    .tint(.white.opacity(0.8))
                    .padding(.leading, 16)
                #if os(xrOS)
                    .glassBackgroundEffect()
                #endif
                if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                    audioButton(audioTracks: audioTracks)
                    #if os(xrOS)
                        .aspectRatio(1, contentMode: .fit)
                        .glassBackgroundEffect()
                    #endif
                }
                Spacer()
                #if !os(tvOS) && !os(xrOS)
                if config.playerLayer?.player.allowsExternalPlayback == true {
                    AirPlayView().fixedSize()
                }
                #endif
                #if !os(xrOS)
                contentModeButton
                #endif
            }
            Spacer()
            #if !os(xrOS)
            HStack {
                Spacer()
                KSVideoPlayerViewBuilder.backwardButton(config: config)
                Spacer()
                KSVideoPlayerViewBuilder.playButton(config: config)
                Spacer()
                KSVideoPlayerViewBuilder.forwardButton(config: config)
                Spacer()
            }
            Spacer()
            HStack {
                KSVideoPlayerViewBuilder.titleView(title: title, config: config)
                Spacer()
                playbackRateButton
                pipButton
                KSVideoPlayerViewBuilder.recordButton(config: config)
                subtitleButton
                infoButton
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
                    contentModeButton
                    subtitleButton
                    playbackRateButton
                    infoButton
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
        #endif
    }

    private var volumeSlider: some View {
        Slider(value: $config.playbackVolume, in: 0 ... 1)
            .onChange(of: config.playbackVolume) { newValue in
                config.isMuted = newValue == 0
            }
    }

    private var contentModeButton: some View {
        KSVideoPlayerViewBuilder.contentModeButton(config: config)
    }

    private func audioButton(audioTracks: [MediaPlayerTrack]) -> some View {
        MenuView(selection: Binding {
            audioTracks.first { $0.isEnabled }?.trackID
        } set: { value in
            if let track = audioTracks.first(where: { $0.trackID == value }) {
                config.playerLayer?.player.select(track: track)
            }
        }) {
            ForEach(audioTracks, id: \.trackID) { track in
                Text(track.description).tag(track.trackID as Int32?)
            }
        } label: {
            Image(systemName: "waveform.circle.fill")
            #if os(xrOS)
                .padding()
                .clipShape(Circle())
            #endif
        }
    }

    private var subtitleButton: some View {
        KSVideoPlayerViewBuilder.subtitleButton(config: config)
    }

    private var playbackRateButton: some View {
        KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $config.playbackRate)
    }

    private var pipButton: some View {
        Button {
            config.playerLayer?.isPipActive.toggle()
        } label: {
            Image(systemName: "rectangle.on.rectangle.circle.fill")
        }
    }

    private var infoButton: some View {
        KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
    }
}

@available(iOS 15, tvOS 16, macOS 12, *)
public struct MenuView<Label, SelectionValue, Content>: View where Label: View, SelectionValue: Hashable, Content: View {
    public let selection: Binding<SelectionValue>
    @ViewBuilder
    public let content: () -> Content
    @ViewBuilder
    public let label: () -> Label
    @State
    private var showMenu = false
    public var body: some View {
        if #available(tvOS 17, *) {
            Menu {
                Picker(selection: selection) {
                    content()
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                label()
            }
            .menuIndicator(.hidden)
        } else {
            Picker(selection: selection, content: content, label: label)
            #if !os(macOS)
                .pickerStyle(.navigationLink)
            #endif
                .frame(height: 50)
            #if os(tvOS)
                .frame(width: 110)
            #endif
        }
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
                Slider(value: Binding {
                    Float(model.currentTime)
                } set: { newValue, _ in
                    model.currentTime = Int(newValue)
                }, in: 0 ... Float(model.totalTime)) { onEditingChanged in
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
            Text("Live Streaming")
        }
    }
}

extension EventModifiers {
    static let none = Self()
}

public struct VideoSubtitleView: View {
    @ObservedObject
    fileprivate var model: SubtitleModel
    public init(model: SubtitleModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            ForEach(model.parts) { part in
                part.view(isHDR: model.isHDR)
            }
        }
        // 禁止字幕视图交互，以免抢占视图的点击事件或其它手势事件
        .allowsHitTesting(false)
        .ksIgnoresSafeArea()
    }

    fileprivate static func imageView(_ image: UIImage) -> some View {
        #if enableFeatureLiveText && canImport(VisionKit) && !targetEnvironment(simulator)
        if #available(macCatalyst 17.0, *) {
            return LiveTextImage(uiImage: image)
        } else {
            return Image(uiImage: image)
                .resizable()
        }
        #else
        return Image(uiImage: image)
            .resizable()
        #endif
    }
}

private extension SubtitlePart {
    @MainActor
    func view(isHDR: Bool) -> some View {
        Group {
            switch self.render {
            case let .left(info):
                GeometryReader { geometry in
                    // 不能加scaledToFit。不然的话图片的缩放比率会有问题。
                    let rect = info.displaySize.convert(rect: info.rect, toSize: geometry.size)
                    VideoSubtitleView.imageView(info.image)
                        .if(isHDR) {
                            $0.allowedDynamicRange()
                        }
                        .offset(CGSize(width: rect.origin.x, height: rect.origin.y))
                        .frame(width: rect.width, height: rect.height)
                }
            case let .right(text):
                VStack {
                    let textPosition = self.textPosition ?? KSOptions.textPosition
                    if textPosition.verticalAlign == .bottom || textPosition.verticalAlign == .center {
                        Spacer()
                    }
                    text.view
                        .italic(value: KSOptions.textItalic)
                        .font(Font(KSOptions.textFont))
                        .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                        .foregroundColor(KSOptions.textColor)
                        .background(KSOptions.textBackgroundColor)
                        .multilineTextAlignment(.center)
                        .alignmentGuide(textPosition.horizontalAlign) {
                            $0[.leading]
                        }
                        .padding(textPosition.edgeInsets)
                    #if !os(tvOS)
                        .textSelection()
                    #endif
                    if textPosition.verticalAlign == .top || textPosition.verticalAlign == .center {
                        Spacer()
                    }
                }
            }
        }
    }
}

extension NSAttributedString {
    var view: some View {
        if #available(macOS 12, iOS 15, tvOS 15, *), !KSOptions.stripSutitleStyle {
            Text(AttributedString(self))
        } else {
            Text(string)
        }
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
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
                        Label("Video Track", systemImage: "video.fill")
                    }

                    Picker("Video Display Type", selection: Binding {
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
                    LabeledContent("Video Type", value: (videoTracks.first { $0.isEnabled }?.dynamicRange ?? .sdr).description)
                    LabeledContent("Stream Type", value: (videoTracks.first { $0.isEnabled }?.fieldOrder ?? .progressive).description)
                }
                TextField("Sutitle delay", value: Binding {
                    playerLayer.subtitleModel.subtitleDelay
                } set: { value in
                    playerLayer.subtitleModel.subtitleDelay = value
                }, format: .number)
                TextField("Title", text: $subtitleTitle)
                Button("Search Sutitle") {
                    playerLayer.subtitleModel.searchSubtitle(query: subtitleTitle, languages: ["zh-cn"])
                }
                .buttonStyle(.bordered)

                if let dynamicInfo = playerLayer.player.dynamicInfo {
                    DynamicInfoView(dynamicInfo: dynamicInfo)
                }
                let fileSize = playerLayer.player.fileSize
                if fileSize > 0 {
                    LabeledContent("File Size", value: fileSize.kmFormatted + "B")
                }
            } else {
                Text("Loading...")
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst) || os(xrOS)
        .toolbar {
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        #endif
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
public struct DynamicInfoView: View {
    @ObservedObject
    fileprivate var dynamicInfo: DynamicInfo
    public var body: some View {
        LabeledContent("Display FPS", value: dynamicInfo.displayFPS, format: .number)
        LabeledContent("Audio Video sync", value: dynamicInfo.audioVideoSyncDiff, format: .number)
        LabeledContent("Dropped Frames", value: dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount, format: .number)
        LabeledContent("Bytes Read", value: dynamicInfo.bytesRead.kmFormatted + "B")
        LabeledContent("Audio bitrate", value: dynamicInfo.audioBitrate.kmFormatted + "bps")
        LabeledContent("Video bitrate", value: dynamicInfo.videoBitrate.kmFormatted + "bps")
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
public struct PlatformView<Content: View>: View {
    private let content: () -> Content
    public var body: some View {
        #if os(tvOS)
        // tvos需要加NavigationStack，不然无法出现下拉框。iOS不能加NavigationStack，不然会丢帧。
        NavigationStack {
            ScrollView {
                content()
                    .padding()
            }
        }
        .pickerStyle(.navigationLink)
        #else
        Form {
            content()
        }
        .formStyle(.grouped)
        #endif
    }

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct KSVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "http://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")!
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
