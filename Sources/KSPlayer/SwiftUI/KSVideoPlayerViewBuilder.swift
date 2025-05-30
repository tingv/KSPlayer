//
//  KSVideoPlayerViewBuilder.swift
//
//
//  Created by Ian Magallan Bosch on 17.03.24.
//

import SwiftUI

@available(iOS 15.0, macOS 12.0, tvOS 15.0, *)
@MainActor
public enum KSVideoPlayerViewBuilder {
    @ViewBuilder
    static func contentModeButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isScaleAspectFill.toggle()
        } label: {
            Image(systemName: config.isScaleAspectFill ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                .menuLabelStyle()
        }
        .borderlessButton()
    }

    @ViewBuilder
    static func subtitleButton(config: KSVideoPlayer.Coordinator) -> some View {
        MenuView(selection: Binding {
            config.playerLayer?.subtitleModel.selectedSubtitleInfo?.subtitleID
        } set: { value in
            let info = config.playerLayer?.subtitleModel.subtitleInfos.first { $0.subtitleID == value }
            // 需要先调用select(track。 因为里面判断了isEnabled
            if let info = info as? MediaPlayerTrack {
                // 因为图片字幕想要实时的显示，那就需要seek。所以需要走select track
                config.playerLayer?.player.select(track: info)
            }
            config.playerLayer?.subtitleModel.selectedSubtitleInfo = info
        }) {
            Text("Off").tag(nil as String?)
            ForEach(config.playerLayer?.subtitleModel.subtitleInfos ?? [], id: \.subtitleID) { track in
                Text(track.name).tag(track.subtitleID as String?)
            }
        } label: {
            Image(systemName: "text.bubble")
        }
    }

    @ViewBuilder
    static func playbackRateButton(playbackRate: Binding<Float>) -> some View {
        MenuView(selection: playbackRate) {
            ForEach([0.5, 1.0, 1.25, 1.5, 2.0] as [Float]) { value in
                // 需要有一个变量text。不然会自动帮忙加很多0
                let text = "\(value) x"
                Text(text).tag(value)
            }
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
    }

    @ViewBuilder
    static func titleView(title: String, config: KSVideoPlayer.Coordinator) -> some View {
        Group {
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(minWidth: 100, alignment: .leading)
            ProgressView()
                .opacity((config.state == .buffering || config.playerLayer?.player.playbackState == .seeking) ? 1 : 0)
        }
    }

    @ViewBuilder
    static func muteButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isMuted.toggle()
        } label: {
            Image(systemName: config.isMuted ? speakerDisabledSystemName : speakerSystemName)
                .menuLabelStyle()
        }
        .borderlessButton()
    }

    @ViewBuilder
    static func infoButton(showVideoSetting: Binding<Bool>) -> some View {
        Button {
            showVideoSetting.wrappedValue.toggle()
        } label: {
            Image(systemName: "info.circle")
                .menuLabelStyle()
        }
        .borderlessButton()
        // iOS 模拟器加keyboardShortcut会导致KSVideoPlayer.Coordinator无法释放。真机不会有这个问题
        #if !os(tvOS)
            .keyboardShortcut("i", modifiers: [.command])
        #endif
    }

    @ViewBuilder
    static func recordButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isRecord.toggle()
        } label: {
            Image(systemName: config.isRecord ? "video.fill" : "video")
                .menuLabelStyle()
        }
        .borderlessButton()
    }

    @ViewBuilder
    static func volumeSlider(config: KSVideoPlayer.Coordinator, volume: Binding<Float>) -> some View {
        Slider(value: volume, in: 0 ... 1)
            .accentColor(.clear)
            .onChange(of: config.playbackVolume) { newValue in
                config.isMuted = newValue == 0
            }
    }

    @ViewBuilder
    static func audioButton(config: KSVideoPlayer.Coordinator, audioTracks: [MediaPlayerTrack]) -> some View {
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
            #if os(visionOS)
                .padding()
                .clipShape(Circle())
            #endif
        }
    }

    @ViewBuilder
    static func pipButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            if let playerLayer = config.playerLayer as? KSComplexPlayerLayer {
                if playerLayer.isPictureInPictureActive {
                    playerLayer.pipStop(restoreUserInterface: true)
                } else {
                    playerLayer.pipStart()
                }
            }
        } label: {
            Image(systemName: "pip")
                .menuLabelStyle()
        }
        .borderlessButton()
    }

    @ViewBuilder
    static func backwardButton(config: KSVideoPlayer.Coordinator) -> some View {
        if config.playerLayer?.player.seekable ?? false {
            Button {
                config.skip(interval: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .centerControlButtonStyle()
            }
            #if !os(tvOS)
            .keyboardShortcut(.leftArrow, modifiers: .none)
            #endif
        }
    }

    @ViewBuilder
    static func forwardButton(config: KSVideoPlayer.Coordinator) -> some View {
        if config.playerLayer?.player.seekable ?? false {
            Button {
                config.skip(interval: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .centerControlButtonStyle()
            }
            #if !os(tvOS)
            .keyboardShortcut(.rightArrow, modifiers: .none)
            #endif
        }
    }

    @ViewBuilder
    static func playButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            if config.state.isPlaying {
                config.playerLayer?.pause()
            } else {
                config.playerLayer?.play()
            }
        } label: {
            Image(systemName: config.state.systemName)
            #if os(iOS)
                .centerControlButtonStyle()
            #elseif os(tvOS)
                .menuLabelStyle()
            #endif
        }
        .borderlessButton()
        #if os(visionOS)
            .contentTransition(.symbolEffect(.replace))
        #endif
        #if !os(tvOS)
        .keyboardShortcut(.space, modifiers: .none)
        #endif
    }

    #if canImport(UIKit) && !os(tvOS)
    @ViewBuilder
    static var landscapeButton: some View {
        Button {
            KSOptions.supportedInterfaceOrientations = UIApplication.isLandscape ? .portrait : .landscapeLeft
            UIViewController.attemptRotationToDeviceOrientation()
        } label: {
            Image(systemName: UIApplication.isLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .menuLabelStyle()
        }
    }
    #endif
}

private extension View {
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, *)
    func centerControlButtonStyle() -> some View {
        font(.system(.title, design: .rounded).bold())
            .imageScale(.large)
            .foregroundStyle(.white)
            .padding(12)
            .contentShape(.rect)
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, *)
public extension KSVideoPlayerViewBuilder {
    static var speakerSystemName: String {
        #if os(visionOS) || os(macOS)
        "speaker.fill"
        #else
        "speaker.wave.2.fill"
        #endif
    }

    static var speakerDisabledSystemName: String {
        "speaker.slash.fill"
    }
}

extension KSPlayerState {
    var systemName: String {
        if self == .error {
            return "play.slash.fill"
        } else if self == .playedToTheEnd {
            #if os(visionOS) || os(macOS)
            return "restart.circle"
            #else
            return "restart.circle.fill"
            #endif
        } else if isPlaying {
            return "pause.fill"
        } else {
            return "play.fill"
        }
    }
}
