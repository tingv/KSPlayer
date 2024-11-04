//
//  KSPictureInPictureController.swift
//  KSPlayer
//
//  Created by kintan on 2023/1/28.
//

import AVKit

@MainActor
public protocol KSPictureInPictureProtocol: AnyObject {
    var isPictureInPictureActive: Bool { get }
    @available(tvOS 14.0, *)
    var delegate: AVPictureInPictureControllerDelegate? { get set }
    init?(playerLayer: AVPlayerLayer)
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    init(contentSource: AVPictureInPictureController.ContentSource)
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    func invalidatePlaybackState()

    func start(layer: KSComplexPlayerLayer)
    func didStart(layer: KSComplexPlayerLayer)
    func stop(restoreUserInterface: Bool)
    static func mute()
}

@MainActor
@available(tvOS 14.0, *)
public class KSPictureInPictureController: AVPictureInPictureController, KSPictureInPictureProtocol {
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    override public required init(contentSource: AVPictureInPictureController.ContentSource) {
        super.init(contentSource: contentSource)
    }

    public func start(layer _: KSComplexPlayerLayer) {
        startPictureInPicture()
    }

    public func didStart(layer _: KSComplexPlayerLayer) {
        #if canImport(UIKit)
        // 直接退到后台
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        #endif
    }

    public func stop(restoreUserInterface _: Bool) {
        stopPictureInPicture()
    }

    public static func mute() {}
}

@MainActor
@available(tvOS 14.0, *)
public class KSpopPictureInPictureController: AVPictureInPictureController, KSPictureInPictureProtocol {
    static var layer: KSComplexPlayerLayer?
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    override public required init(contentSource: AVPictureInPictureController.ContentSource) {
        super.init(contentSource: contentSource)
    }

    public func start(layer _: KSComplexPlayerLayer) {
        startPictureInPicture()
    }

    public func didStart(layer: KSComplexPlayerLayer) {
        #if canImport(UIKit)
        guard let viewController = layer.player.view.viewController else { return }
        let originalViewController: UIViewController
        if let navigationController = viewController.navigationController, navigationController.viewControllers.count == 1 {
            originalViewController = navigationController
        } else {
            originalViewController = viewController
        }
        if let navigationController = originalViewController.navigationController {
            navigationController.popViewController(animated: true)
        } else {
            viewController.dismiss(animated: true)
        }
        #endif
        KSpopPictureInPictureController.layer?.stop()
        KSpopPictureInPictureController.layer = layer
    }

    public func stop(restoreUserInterface _: Bool) {
        stopPictureInPicture()
        DispatchQueue.main.async {
            KSpopPictureInPictureController.layer?.stop()
            KSpopPictureInPictureController.layer = nil
        }
    }

    public static func mute() {
        layer?.player.isMuted = true
    }
}
