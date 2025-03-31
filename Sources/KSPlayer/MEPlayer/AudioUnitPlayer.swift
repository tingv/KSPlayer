//
//  AudioUnitPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/16.
//

import AudioToolbox
import AVFAudio
import CoreAudio

/**
  内存占用最小，但是少了一些功能：只有macOS支持音量调节 其他OS不支持。但是音响效果是最好的，解决了下面几个问题。
  1. Sound dynamics are deficient overall, regardless of the multichannel sound tracks played.
  2. Some surround effects between the speakers are absent.
  3. The subwoofer's bass reproduction is not at the expected level (underpowered).
  倍数实现使用的是ffmpg的filter，会导致无法实时生效，但是这个也有另外一个好处是 频繁的进行倍速播放不会crash。其他的音频输出是会有概率出现的，
 **/
public final class AudioUnitPlayer: AudioOutput, @unchecked Sendable {
    private var audioUnitForOutput: AudioUnit!
    private var currentRenderReadOffset = UInt32(0)
    private var sourceNodeAudioFormat: AVAudioFormat?
    public weak var renderSource: AudioOutputRenderSourceDelegate?
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    private var isPlaying = false
    public func play() {
        if !isPlaying {
            isPlaying = true
            if currentRender == nil {
                currentRender = renderSource?.getAudioOutputRender()
            }
            if let currentRender {
                renderSource?.setAudio(time: currentRender.cmtime, position: -1)
            }
            AudioOutputUnitStart(audioUnitForOutput)
        }
    }

    public func pause() {
        if isPlaying {
            isPlaying = false
            AudioOutputUnitStop(audioUnitForOutput)
        }
    }

    public var playbackRate: Float = 1
    public var isMuted: Bool = false
    private var outputLatency = TimeInterval(0)
    public init() {
        var descriptionForOutput = AudioComponentDescription()
        descriptionForOutput.componentType = kAudioUnitType_Output
        descriptionForOutput.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForOutput.componentSubType = kAudioUnitSubType_DefaultOutput
        #else
        descriptionForOutput.componentSubType = kAudioUnitSubType_RemoteIO
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
        let nodeForOutput = AudioComponentFindNext(nil, &descriptionForOutput)
        AudioComponentInstanceNew(nodeForOutput!, &audioUnitForOutput)
        var value = UInt32(1)
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0,
                             &value,
                             UInt32(MemoryLayout<UInt32>.size))
    }

    public func prepare(audioFormat: AVAudioFormat) {
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        sourceNodeAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(audioFormat.sampleRate)
        #endif
        var audioStreamBasicDescription = audioFormat.formatDescription.audioStreamBasicDescription
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0,
                             &audioStreamBasicDescription,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        let channelLayout = audioFormat.channelLayout?.layout
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_AudioChannelLayout,
                             kAudioUnitScope_Input, 0,
                             channelLayout,
                             UInt32(MemoryLayout<AudioChannelLayout>.size))
        var inputCallbackStruct = renderCallbackStruct()
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0,
                             &inputCallbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        addRenderNotify(audioUnit: audioUnitForOutput)
        AudioUnitInitialize(audioUnitForOutput)
    }

    public func flush() {
        currentRender = nil
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    public func invalidate() {
        AudioUnitUninitialize(audioUnitForOutput)
    }

    public var volume: Float {
        get {
            var volume = AudioUnitParameterValue(0.0)
            AudioUnitGetParameter(audioUnitForOutput, kHALOutputParam_Volume, kAudioUnitScope_Input, 0, &volume)
            return volume
        }
        set {
            AudioUnitSetParameter(audioUnitForOutput, kHALOutputParam_Volume, kAudioUnitScope_Input, 0, newValue, 0)
        }
    }
}

extension AudioUnitPlayer {
    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
            guard let ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfFrames: inNumberFrames)
            return noErr
        }
        return inputCallbackStruct
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

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
                    if isMuted {
                        memset(destination + Int(ioData[i].mDataByteSize - mDataByteSize), 0, Int(bytesToCopy))
                    } else {
                        (destination + Int(ioData[i].mDataByteSize - mDataByteSize)).copyMemory(from: source + Int(currentRenderReadOffset), byteCount: Int(bytesToCopy))
                    }
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
}
