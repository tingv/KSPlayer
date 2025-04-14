//
//  AudioRendererPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2022/12/2.
//

import AVFoundation
import Foundation

/**
 支持airpod的空间音频。
 */
public class AudioRendererPlayer: AudioOutput {
    // AVSampleBufferAudioRenderer 不需要计算outputLatency，会自动计算。
    public var outputLatency = TimeInterval(0)
    public var playbackRate: Float = 1 {
        didSet {
            if !isPaused {
                synchronizer.rate = playbackRate
            }
        }
    }

    public var volume: Float {
        get {
            renderer.volume
        }
        set {
            renderer.volume = newValue
        }
    }

    public var isMuted: Bool {
        get {
            renderer.isMuted
        }
        set {
            renderer.isMuted = newValue
        }
    }

    var isPaused: Bool {
        synchronizer.rate == 0
    }

    public weak var renderSource: AudioOutputRenderSourceDelegate?
    private var periodicTimeObserver: Any?
    private var flushTime = true
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let serializationQueue = DispatchQueue(label: "ks.player.serialization.queue")
    public required init() {
        synchronizer.addRenderer(renderer)
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        }
        if #available(tvOS 15.0, iOS 15.0, macOS 12.0, *) {
            renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        }
    }

    public func prepare(audioFormat: AVAudioFormat) {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(audioFormat.sampleRate)
        #endif
        renderer.requestMediaDataWhenReady(on: serializationQueue) { [weak self] in
            guard let self else {
                return
            }
            request()
        }
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        periodicTimeObserver = synchronizer.addPeriodicTimeObserver(forInterval: CMTime(value: 100, timescale: CMTimeScale(audioFormat.sampleRate)), queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            renderSource?.setAudio(time: time, position: -1)
        }
    }

    public func play() {
        let time: CMTime
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *), renderer.hasSufficientMediaDataForReliablePlaybackStart {
            // 判断是否有足够的缓存，有的话就用当前的时间。seek的话，需要清空缓存，这样才能取到最新的时间。
            time = synchronizer.currentTime()
        } else {
            /// 连接蓝牙音响的话，hasSufficientMediaDataForReliablePlaybackStart会一直返回false,
            /// 所以要兜底判断要不要从数据源头获取最新的时间，
            if flushTime, let currentRender = renderSource?.getAudioOutputRender() {
                flushTime = false
                time = currentRender.cmtime
            } else {
                time = synchronizer.currentTime()
            }
        }

        renderSource?.setAudio(time: time, position: -1)
        // 一定要用setRate(_ rate: Float, time: CMTime)，只改rate的话，那seek会有问题
        //        synchronizer.rate = playbackRate
        synchronizer.setRate(playbackRate, time: time)
    }

    public func pause() {
        synchronizer.rate = 0
    }

    public func flush() {
        renderer.flush()
        flushTime = true
    }

    public func invalidate() {
        renderer.stopRequestingMediaData()
        flush()
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        synchronizer.rate = 0
    }

    private func request() {
        guard !isPaused, var render = renderSource?.getAudioOutputRender() else {
            return
        }
        var array = [render]
        let loopCount = Int32(render.audioFormat.sampleRate) / 10 / Int32(render.numberOfSamples)
        if loopCount > 0 {
            for _ in 0 ..< loopCount * 2 {
                if let render = renderSource?.getAudioOutputRender() {
                    array.append(render)
                }
                if array.count == loopCount {
                    break
                }
            }
        }
        if array.count > 1 {
            render = AudioFrame(array: array)
        }
        if let sampleBuffer = render.toCMSampleBuffer() {
            let channelCount = render.audioFormat.channelCount
            renderer.audioTimePitchAlgorithm = channelCount > 2 ? .spectral : .timeDomain
            renderer.enqueue(sampleBuffer)
            #if !os(macOS)
            if AVAudioSession.sharedInstance().preferredInputNumberOfChannels != channelCount {
                try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(channelCount))
                try? AVAudioSession.sharedInstance().setPreferredSampleRate(render.audioFormat.sampleRate)
            }
            #endif
        }
        /// 连接蓝牙音响的话， 要缓存100多秒isReadyForMoreMediaData才会返回false，
        /// 非蓝牙音响只要1.3s就返回true了。还没找到解决办法
//        if !renderer.isReadyForMoreMediaData {
//            let diff = render.seconds - synchronizer.currentTime().seconds
//            KSLog("[audio] AVSampleBufferAudioRenderer cache \(diff)")
//        }
    }
}
