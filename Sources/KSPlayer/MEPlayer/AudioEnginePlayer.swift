//
//  AudioEnginePlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import AVFoundation
import CoreAudio

public protocol AudioOutput: FrameOutput {
    var renderSource: AudioOutputRenderSourceDelegate? { get set }
    @MainActor
    var playbackRate: Float { get set }
//    @MainActor
    var volume: Float { get set }
    // macOS无法获取音频设备的延迟，所以需要开发者自己设置下。
    var outputLatency: TimeInterval { get set }
//    @MainActor
    var isMuted: Bool { get set }
    @MainActor
    init()
    @MainActor
    func prepare(audioFormat: AVAudioFormat)
}

public protocol AudioDynamicsProcessor {
    var audioUnitForDynamicsProcessor: AudioUnit { get }
}

public extension AudioDynamicsProcessor {
    var attackTime: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var releaseTime: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var threshold: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var expansionRatio: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var overallGain: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }
}

public final class AudioEngineDynamicsPlayer: AudioEnginePlayer, AudioDynamicsProcessor {
    //    private let reverb = AVAudioUnitReverb()
    public let nbandEQ = AVAudioUnitEQ()
    //    private let distortion = AVAudioUnitDistortion()
    //    private let delay = AVAudioUnitDelay()
    private let dynamicsProcessor = AVAudioUnitEffect(audioComponentDescription:
        AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                  componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0,
                                  componentFlagsMask: 0))
    public var audioUnitForDynamicsProcessor: AudioUnit {
        dynamicsProcessor.audioUnit
    }

    override func audioNodes() -> [AVAudioNode] {
        var nodes: [AVAudioNode] = [nbandEQ, dynamicsProcessor]
        nodes.append(contentsOf: super.audioNodes())
        return nodes
    }

    public required init() {
        super.init()
        engine.attach(nbandEQ)
        engine.attach(dynamicsProcessor)
    }
}

public class AudioEnginePlayer: AudioOutput, @unchecked Sendable {
    public let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var sourceNodeAudioFormat: AVAudioFormat?
    private let timePitch = AVAudioUnitTimePitch()
    private var currentRenderReadOffset = UInt32(0)
    public var outputLatency = TimeInterval(0)
    public weak var renderSource: AudioOutputRenderSourceDelegate?
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    public var playbackRate: Float {
        get {
            timePitch.rate
        }
        set {
            timePitch.rate = min(32, max(1 / 32, newValue))
        }
    }

    public var volume: Float {
        get {
            sourceNode?.volume ?? 1
        }
        set {
            sourceNode?.volume = newValue
        }
    }

    public var isMuted: Bool {
        get {
            engine.mainMixerNode.outputVolume == 0.0
        }
        set {
            engine.mainMixerNode.outputVolume = newValue ? 0.0 : 1.0
        }
    }

    public required init() {
        engine.attach(timePitch)
        if let audioUnit = engine.outputNode.audioUnit {
            addRenderNotify(audioUnit: audioUnit)
        }
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    public func prepare(audioFormat: AVAudioFormat) {
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        let isRunning = engine.isRunning
        // 第一次进入需要调用reset和stop。不然会报错from AU (0x1038d6c10): aufc/conv/appl, render err: -10867
        engine.reset()
        engine.stop()
        sourceNodeAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(audioFormat.sampleRate)
        #endif
        KSLog("[audio] outputFormat AudioFormat: \(audioFormat)")
        if let channelLayout = audioFormat.channelLayout {
            KSLog("[audio] outputFormat channelLayout \(channelLayout.channelDescriptions)")
        }
        sourceNode = AVAudioSourceNode(format: audioFormat) { @Sendable [weak self] _, timestamp, frameCount, audioBufferList in
            if timestamp.pointee.mSampleTime == 0 {
                return noErr
            }
            self?.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(audioBufferList), numberOfFrames: frameCount)
            return noErr
        }
        guard let sourceNode else {
            return
        }
        KSLog("[audio] new sourceNode inputFormat: \(sourceNode.inputFormat(forBus: 0))")
        engine.attach(sourceNode)
        var nodes: [AVAudioNode] = [sourceNode]
        nodes.append(contentsOf: audioNodes())
        if audioFormat.channelCount > 2 {
            nodes.append(engine.outputNode)
        }
        // 一定要传入format，这样多音轨音响才不会有问题。
        engine.connect(nodes: nodes, format: audioFormat)
        engine.prepare()
        if isRunning {
            try? engine.start()
            // 从多声道切换到2声道马上调用start会不生效。需要异步主线程才可以
            DispatchQueue.main.async { [weak self] in
                self?.play()
            }
        }
    }

    func audioNodes() -> [AVAudioNode] {
        [timePitch, engine.mainMixerNode]
    }

    public func play() {
        if !engine.isRunning {
            do {
                if currentRender == nil {
                    currentRender = renderSource?.getAudioOutputRender()
                }
                if let currentRender {
                    renderSource?.setAudio(time: currentRender.cmtime, position: -1)
                }
                try engine.start()
            } catch {
                KSLog(error)
            }
        }
    }

    public func pause() {
        if engine.isRunning {
            engine.pause()
        }
    }

    public func flush() {
        currentRender = nil
        #if !os(macOS)
        // 这个要在主线程执行，如果在音频的线程，那就会有中断杂音
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioEnginePlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

//    private func addRenderCallback(audioUnit: AudioUnit, streamDescription: UnsafePointer<AudioStreamBasicDescription>) {
//        _ = AudioUnitSetProperty(audioUnit,
//                                 kAudioUnitProperty_StreamFormat,
//                                 kAudioUnitScope_Input,
//                                 0,
//                                 streamDescription,
//                                 UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
//        var inputCallbackStruct = AURenderCallbackStruct()
//        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
//        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
//            guard let ioData else {
//                return noErr
//            }
//            let `self` = Unmanaged<AudioEnginePlayer>.fromOpaque(refCon).takeUnretainedValue()
//            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfFrames: inNumberFrames)
//            return noErr
//        }
//        _ = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &inputCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
//    }

    private func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer, numberOfFrames _: UInt32) {
        guard ioData.count > 0 else {
            return
        }
        var mDataByteSize = ioData[0].mDataByteSize
        while mDataByteSize > 0 {
            if currentRender == nil {
                currentRender = renderSource?.getAudioOutputRender()
            }
            guard let currentRender else {
                break
            }
            let residueLinesize = UInt32(currentRender.dataSize) - currentRenderReadOffset
            guard residueLinesize > 0 else {
                self.currentRender = nil
                continue
            }
            if sourceNodeAudioFormat != currentRender.audioFormat {
                runOnMainThread { [weak self] in
                    guard let self else {
                        return
                    }
                    prepare(audioFormat: currentRender.audioFormat)
                }
                return
            }
            let bytesToCopy = min(mDataByteSize, residueLinesize)
            for i in 0 ..< min(ioData.count, currentRender.data.count) {
                if let source = currentRender.data[i], let destination = ioData[i].mData {
                    (destination + Int(ioData[i].mDataByteSize - mDataByteSize)).copyMemory(from: source + Int(currentRenderReadOffset), byteCount: Int(bytesToCopy))
                }
            }
            currentRenderReadOffset += bytesToCopy
            mDataByteSize -= bytesToCopy
        }
        if mDataByteSize > 0 {
            for i in 0 ..< ioData.count {
                memset(ioData[i].mData! + Int(ioData[i].mDataByteSize - mDataByteSize), 0, Int(mDataByteSize))
            }
        }
    }

    private func audioPlayerDidRenderSample(sampleTimestamp _: AudioTimeStamp) {
        if let currentRender {
            let currentPreparePosition = currentRender.timestamp + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.dataSize)
            if currentPreparePosition > 0 {
                var time = currentRender.timebase.cmtime(for: currentPreparePosition)
                if outputLatency != 0 {
                    /// AVSampleBufferAudioRenderer不需要处理outputLatency。其他音频输出的都要处理。
                    /// 没有蓝牙的话，outputLatency为0.015，有蓝牙耳机的话为0.176
                    time = time - CMTime(seconds: outputLatency, preferredTimescale: time.timescale)
                }
                renderSource?.setAudio(time: time, position: currentRender.position)
            }
        }
    }

    public func invalidate() {
        engine.reset()
        engine.stop()
    }
}

extension AVAudioEngine {
    func connect(nodes: [AVAudioNode], format: AVAudioFormat?) {
        if nodes.count < 2 {
            return
        }
        for i in 0 ..< nodes.count - 1 {
            connect(nodes[i], to: nodes[i + 1], format: format)
        }
    }
}
