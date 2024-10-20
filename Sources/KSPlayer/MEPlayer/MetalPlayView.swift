//
//  MetalPlayView.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import AVFoundation
import Combine
import CoreMedia
import FFmpegKit
import QuartzCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@MainActor
public protocol VideoOutput: FrameOutput {
    var options: KSOptions { get set }
//    AVSampleBufferDisplayLayer和CAMetalLayer无法使用截图方法 render(in ctx: CGContext)，所以要保存pixelBuffer来进行视频截图。
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var pixelBuffer: PixelBufferProtocol? { get set }
    init(options: KSOptions)
    func readNextFrame()
    func enterForeground()
}

public final class MetalPlayView: UIView, VideoOutput {
    public var displayLayer: AVSampleBufferDisplayLayer {
        displayView.displayLayer
    }

    private var isDovi: Bool = false
    private var formatDescription: CMFormatDescription? {
        didSet {
            if let formatDescription {
                options.updateVideo(refreshRate: fps, isDovi: isDovi, formatDescription: formatDescription)
            }
        }
    }

    private var fps = Float(60) {
        didSet {
            if fps != oldValue {
                if options.preferredFrame(fps: fps) {
                    let preferredFramesPerSecond = ceil(fps)
                    if #available(iOS 15.0, tvOS 15.0, macOS 14.0, *) {
                        /// 一定要用preferredFrameRateRange，并且maximum不能两倍。
                        /// 不然在60fps的tvos播放25fps的视频无法很丝滑
                        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: preferredFramesPerSecond, maximum: preferredFramesPerSecond, __preferred: preferredFramesPerSecond)
                    } else {
                        displayLink.preferredFramesPerSecond = Int(preferredFramesPerSecond)
                    }
                }
                if let formatDescription {
                    options.updateVideo(refreshRate: fps, isDovi: isDovi, formatDescription: formatDescription)
                }
            }
        }
    }

    public var pixelBuffer: PixelBufferProtocol?
    /// 用displayLink会导致锁屏无法draw，
    /// 用DispatchSourceTimer的话，在播放4k视频的时候repeat的时间会变长,
    /// 用MTKView的draw(in:)也是不行，会卡顿
    private var displayLink: CADisplayLink!
//    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    public var options: KSOptions
    public weak var renderSource: OutputRenderSourceDelegate?
    // AVSampleBufferAudioRenderer AVSampleBufferRenderSynchronizer AVSampleBufferDisplayLayer
    private let displayView = AVSampleBufferDisplayView()
    public var drawable: Drawable
    private let metalView = MetalView()
    public init(options: KSOptions) {
        self.options = options
        drawable = metalView.metalLayer
        super.init(frame: .zero)
        addSub(view: displayView)
        addSub(view: metalView)
        metalView.isHidden = true
        //        displayLink = CADisplayLink(block: renderFrame)
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        // 一定要用common。不然在视频上面操作view的话，那就会卡顿了。
        displayLink.add(to: .main, forMode: .common)
        pause()
    }

    public func play() {
        displayLink.isPaused = false
    }

    public func pause() {
        displayLink.isPaused = true
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var contentMode: UIViewContentMode {
        didSet {
            metalView.contentMode = contentMode
            switch contentMode {
            case .scaleToFill:
                displayView.displayLayer.videoGravity = .resize
            case .scaleAspectFit, .center:
                displayView.displayLayer.videoGravity = .resizeAspect
            case .scaleAspectFill:
                displayView.displayLayer.videoGravity = .resizeAspectFill
            default:
                break
            }
        }
    }

    #if canImport(UIKit)
    override public func touchesMoved(_ touches: Set<UITouch>, with: UIEvent?) {
        if options.display.isSphere {
            options.display.touchesMoved(touch: touches.first!)
        } else {
            super.touchesMoved(touches, with: with)
        }
    }
    #else
    override public func touchesMoved(with event: NSEvent) {
        if options.display.isSphere {
            options.display.touchesMoved(touch: event.allTouches().first!)
        } else {
            super.touchesMoved(with: event)
        }
    }
    #endif

    public func flush() {
        pixelBuffer = nil
        if displayView.isHidden {
            drawable.clear()
            if let mtlTextureCache = MetalRender.mtlTextureCache {
                CVMetalTextureCacheFlush(mtlTextureCache, 0)
            }
        } else {
            displayView.displayLayer.flushAndRemoveImage()
        }
    }

    public func invalidate() {
        flush()
        displayLink.invalidate()
    }

    public func readNextFrame() {
        draw(force: true)
    }

    public func enterForeground() {
        // 解决从后台一会儿在进入到前台的时候，displayView黑屏的问题
        if !displayView.isHidden, let pixelBuffer = pixelBuffer?.cvPixelBuffer {
            set(pixelBuffer: pixelBuffer)
        }
    }

    private func addSub(view: UIView) {
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: leftAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    deinit {}
}

extension MetalPlayView {
    @objc private func renderFrame() {
        draw(force: false)
    }

    private func draw(force: Bool) {
        autoreleasepool {
            guard let frame = renderSource?.getVideoOutputRender(force: force) else {
                return
            }
            pixelBuffer = frame.pixelBuffer
            guard let pixelBuffer else {
                return
            }
            isDovi = frame.isDovi
            fps = frame.fps
            let cmtime = frame.cmtime
            let par = pixelBuffer.size
            let sar = pixelBuffer.aspectRatio
            if let dar = options.customizeDar(sar: sar, par: par) {
                pixelBuffer.aspectRatio = CGSize(width: dar.width, height: dar.height * par.width / par.height)
            }
            checkFormatDescription(pixelBuffer: pixelBuffer)
            // 高度太高用AVSampleBufferDisplayLayer在macos播放会导致电脑重启，所以做一下判断
            if let pixelBuffer = pixelBuffer.cvPixelBuffer, options.isUseDisplayLayer(), par.height < 6000 {
                if displayView.isHidden {
                    displayView.isHidden = false
                    metalView.isHidden = true
                    drawable.clear()
                }
                set(pixelBuffer: pixelBuffer)
            } else {
                if !displayView.isHidden {
                    displayView.isHidden = true
                    metalView.isHidden = false
                    displayView.displayLayer.flushAndRemoveImage()
                }
                if frame.doviData != nil, options.display === KSOptions.displayEnumDovi {
                    frame.pixelBuffer.colorspace = CGColorSpace(name: CGColorSpace.itur_2020_PQ_EOTF)
                }
                drawable.draw(frame: frame, display: options.display)
            }
            renderSource?.setVideo(time: cmtime, position: frame.position)
        }
    }

    private func checkFormatDescription(pixelBuffer: PixelBufferProtocol) {
        if formatDescription == nil || !pixelBuffer.matche(formatDescription: formatDescription!) {
            // 宽高不一样，先不用更换AVSampleBufferDisplayView。找不到之前为什么要这么做的记录了。
//            if formatDescription != nil {
//                let videoGravity = displayView.displayLayer.videoGravity
//                displayView.removeFromSuperview()
//                displayView = AVSampleBufferDisplayView()
//                displayView.displayLayer.videoGravity = videoGravity
//                displayView.frame = frame
//                addSubview(displayView)
//            }
            formatDescription = pixelBuffer.formatDescription
        }
    }

    private func set(pixelBuffer: CVPixelBuffer) {
        guard let formatDescription else { return }
        displayView.enqueue(imageBuffer: pixelBuffer, formatDescription: formatDescription)
    }
}

public class MetalView: UIView {
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { CAMetalLayer.self }
    #endif
    public var metalLayer: CAMetalLayer {
        // swiftlint:disable force_cast
        layer as! CAMetalLayer
        // swiftlint:enable force_cast
    }

    public init() {
        super.init(frame: .zero)
        #if !canImport(UIKit)
        layer = CAMetalLayer()
        #endif
        metalLayer.device = MetalRender.device
        metalLayer.framebufferOnly = true
        #if os(tvOS)
        if #available(macOS 15.0, tvOS 18.0, iOS 18.0, visionOS 2.0, *) {
            metalLayer.toneMapMode = .ifSupported
        }
        #endif
//        metalLayer.displaySyncEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class AVSampleBufferDisplayView: UIView {
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    #endif
    var displayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable force_cast
        layer as! AVSampleBufferDisplayLayer
        // swiftlint:enable force_cast
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if !canImport(UIKit)
        layer = AVSampleBufferDisplayLayer()
        #endif
        var controlTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &controlTimebase)
        if let controlTimebase {
            displayLayer.controlTimebase = controlTimebase
            CMTimebaseSetTime(controlTimebase, time: .zero)
            CMTimebaseSetRate(controlTimebase, rate: 1.0)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func enqueue(imageBuffer: CVPixelBuffer, formatDescription: CMVideoFormatDescription) {
        let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        //        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescription: formatDescription, sampleTiming: [timing], sampleBufferOut: &sampleBuffer)
        if let sampleBuffer {
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [NSMutableDictionary], let dic = attachmentsArray.first {
                dic[kCMSampleAttachmentKey_DisplayImmediately] = true
            }
            if #available(macOS 11.0, iOS 14, tvOS 14, *) {
                // 需要先flush在进行enqueue
                if displayLayer.requiresFlushToResumeDecoding {
                    KSLog("[video] AVSampleBufferDisplayLayer requiresFlushToResumeDecoding so flush")
                    displayLayer.flush()
                }
            }
            if displayLayer.isReadyForMoreMediaData {
                displayLayer.enqueue(sampleBuffer)
            } else {
                KSLog("[video] AVSampleBufferDisplayLayer not readyForMoreMediaData. controlTime \(displayLayer.timebase.time) ")
                displayLayer.enqueue(sampleBuffer)
            }
            if displayLayer.status == .failed {
                KSLog("[video] AVSampleBufferDisplayLayer status failed so flush")
                displayLayer.flush()
                //                    if let error = displayLayer.error as NSError?, error.code == -11847 {
                //                        displayLayer.stopRequestingMediaData()
                //                    }
            }
        }
    }
}

#if os(macOS)
import CoreVideo
import RealityFoundation

class CADisplayLink {
    private let displayLink: CVDisplayLink
    private var runloop: RunLoop?
    private var mode = RunLoop.Mode.default
    public var preferredFramesPerSecond = 60
    @available(macOS 12.0, *)
    public var preferredFrameRateRange: CAFrameRateRange {
        get {
            CAFrameRateRange()
        }
        set {}
    }

    public var timestamp: TimeInterval {
        var timeStamp = CVTimeStamp()
        if CVDisplayLinkGetCurrentTime(displayLink, &timeStamp) == kCVReturnSuccess, (timeStamp.flags & CVTimeStampFlags.hostTimeValid.rawValue) != 0 {
            return TimeInterval(timeStamp.hostTime / NSEC_PER_SEC)
        }
        return 0
    }

    public var duration: TimeInterval {
        CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLink)
    }

    public var targetTimestamp: TimeInterval {
        duration + timestamp
    }

    public var isPaused: Bool {
        get {
            !CVDisplayLinkIsRunning(displayLink)
        }
        set {
            if newValue {
                CVDisplayLinkStop(displayLink)
            } else {
                CVDisplayLinkStart(displayLink)
            }
        }
    }

    public init(target: NSObject, selector: Selector) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { [weak self] _, _, _, _, _ in
            guard let self else { return kCVReturnSuccess }
            self.runloop?.perform(selector, target: target, argument: self, order: 0, modes: [self.mode])
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    public init(block: @escaping (() -> Void)) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { _, _, _, _, _ in
            block()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    open func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        self.runloop = runloop
        self.mode = mode
    }

    public func invalidate() {
        isPaused = true
        runloop = nil
        CVDisplayLinkSetOutputHandler(displayLink) { _, _, _, _, _ in
            kCVReturnError
        }
    }
}
#endif
