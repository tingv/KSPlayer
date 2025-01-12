//
//  PlayerToolBar.swift
//  Pods
//
//  Created by kintan on 16/5/21.
//
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import AVKit

public class PlayerToolBar: UIVisualEffectView {

    public let srtButton = UIButton()
    public let timeLabel = UILabel()

    // 工具栏器容器示图
    public var toolBarContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // 进度条/时间 容器
    public var progressContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    public let currentTimeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.textAlignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    public let totalTimeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.textAlignment = .left
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // 时间滑块容器
    public var timeSliderContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGreen.withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // 播放按钮堆栈
    public var playButtonStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillProportionally
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    // 上一集按钮
    public var prevButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(KSOptions.image(named:"playback.prev"), for: .normal)
        if let imageView = button.imageView {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // 播放按钮
    public var playButton: UIButton = {
        let button = UIButton(type: .custom)
        // button.setImage(KSOptions.image(named: "playback.pause"), for: .normal)
        if let imageView = button.imageView {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    //  下一集按钮
    public var nextButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(KSOptions.image(named: "playback.next"), for: .normal)
        if let imageView = button.imageView {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // 播放设置按钮
    public var extendedButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(KSOptions.image(named: "playback.settings"), for: .normal)
        if let imageView = button.imageView {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // AirPlay按钮
    public var airplayButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(KSOptions.image(named: "playback.airplay"), for: .normal)
        if let imageView = button.imageView {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    public let timeSlider = KSSlider()
    public let playbackRateButton = UIButton()
    public let videoSwitchButton = UIButton()
    public let audioSwitchButton = UIButton()
    public let definitionButton = UIButton()
    public let pipButton = UIButton()
    public var onFocusUpdate: ((_ cofusedItem: UIView) -> Void)?
    public var timeType = TimeType.minOrHour {
        didSet {
            if timeType != oldValue {
                let currentTimeText = currentTime.toString(for: timeType)
                let totalTimeText = totalTime.toString(for: timeType)
                currentTimeLabel.text = currentTimeText
                totalTimeLabel.text = totalTimeText
                timeLabel.text = "\(currentTimeText) / \(totalTimeText)"
            }
        }
    }

    public var currentTime: TimeInterval = 0 {
        didSet {
            guard !currentTime.isNaN else {
                currentTime = 0
                return
            }
            if currentTime != oldValue {
                let text = currentTime.toString(for: timeType)
                currentTimeLabel.text = text
                timeLabel.text = "\(text) / \(totalTime.toString(for: timeType))"
                if isLiveStream {
                    timeSlider.value = Float(todayInterval)
                } else {
                    timeSlider.value = Float(currentTime)
                }
            }
        }
    }

    lazy var startDateTimeInteral: TimeInterval = {
        let date = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let startDate = calendar.date(from: components)
        return startDate?.timeIntervalSince1970 ?? 0
    }()

    var todayInterval: TimeInterval {
        Date().timeIntervalSince1970 - startDateTimeInteral
    }

    public var totalTime: TimeInterval = 0 {
        didSet {
            guard !totalTime.isNaN else {
                totalTime = 0
                return
            }
            if totalTime != oldValue {
                let text = totalTime.toString(for: timeType)
                totalTimeLabel.text = text
                timeLabel.text = "\(currentTime.toString(for: timeType)) / \(text)"
                timeSlider.maximumValue = Float(totalTime)
            }
            if isLiveStream {
                timeSlider.maximumValue = Float(60 * 60 * 24)
            }
        }
    }

    public var isLiveStream: Bool {
        totalTime == 0
    }

    public var isSeekable: Bool = true {
        didSet {
            timeSlider.isUserInteractionEnabled = isSeekable
        }
    }

    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)

        // 创建模糊效果
        let blurEffect = UIBlurEffect(style: .dark)
        self.effect = blurEffect

        self.layer.cornerRadius = 12
        self.clipsToBounds = true
        self.translatesAutoresizingMaskIntoConstraints = false

        // 创建活力效果
        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
        let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        vibrancyView.translatesAutoresizingMaskIntoConstraints = false

        // 将 vibrancyView 添加到 toolBar 的 contentView 中
        self.contentView.addSubview(vibrancyView)

        // 设置 vibrancyView 约束
        NSLayoutConstraint.activate([
            vibrancyView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            vibrancyView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            vibrancyView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            vibrancyView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor)
        ])

        initUI()

    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func initUI() {
        let focusColor = UIColor.white
        let tintColor = UIColor.gray

        currentTimeLabel.text = 0.toString(for: timeType)
        totalTimeLabel.text = 0.toString(for: timeType)
        timeLabel.textColor = UIColor(rgb: 0x9B9B9B)
        timeLabel.textAlignment = .left
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        timeLabel.text = "\(0.toString(for: timeType)) / \(0.toString(for: timeType))"
        timeSlider.minimumValue = 0
        timeSlider.trackHeigt = CGFloat(6)
        #if os(iOS)
        if #available(macCatalyst 15.0, iOS 15.0, *) {
            timeSlider.preferredBehavioralStyle = .pad
            timeSlider.maximumTrackTintColor = focusColor.withAlphaComponent(0.2)
            timeSlider.minimumTrackTintColor = focusColor.withAlphaComponent(0.8)
        }
        #endif
        #if !targetEnvironment(macCatalyst)
        timeSlider.maximumTrackTintColor = focusColor.withAlphaComponent(0.2)
        timeSlider.minimumTrackTintColor = focusColor.withAlphaComponent(0.8)
        #endif
        playButton.tag = PlayerButtonType.play.rawValue
        playbackRateButton.tag = PlayerButtonType.rate.rawValue
        playbackRateButton.titleFont = .systemFont(ofSize: 14, weight: .medium)
        playbackRateButton.setTitleColor(focusColor, for: .focused)
        playbackRateButton.setTitleColor(tintColor, for: .normal)
        definitionButton.tag = PlayerButtonType.definition.rawValue
        definitionButton.titleFont = .systemFont(ofSize: 14, weight: .medium)
        definitionButton.setTitleColor(focusColor, for: .focused)
        definitionButton.setTitleColor(tintColor, for: .normal)
        audioSwitchButton.tag = PlayerButtonType.audioSwitch.rawValue
        audioSwitchButton.titleFont = .systemFont(ofSize: 14, weight: .medium)
        audioSwitchButton.setTitleColor(focusColor, for: .focused)
        audioSwitchButton.setTitleColor(tintColor, for: .normal)
        videoSwitchButton.tag = PlayerButtonType.videoSwitch.rawValue
        videoSwitchButton.titleFont = .systemFont(ofSize: 14, weight: .medium)
        videoSwitchButton.setTitleColor(focusColor, for: .focused)
        videoSwitchButton.setTitleColor(tintColor, for: .normal)
        srtButton.tag = PlayerButtonType.srt.rawValue
        srtButton.titleFont = .systemFont(ofSize: 14, weight: .medium)
        srtButton.setTitleColor(focusColor, for: .focused)
        srtButton.setTitleColor(tintColor, for: .normal)
        pipButton.tag = PlayerButtonType.pictureInPicture.rawValue
        pipButton.titleFont = .systemFont(ofSize: 14, weight: .medium)
        pipButton.setTitleColor(focusColor, for: .focused)
        pipButton.setTitleColor(tintColor, for: .normal)

        // 扩展设置按钮
        extendedButton.tag = PlayerButtonType.extended.rawValue
        extendedButton.setTitleColor(focusColor, for: .focused)
        extendedButton.setTitleColor(tintColor, for: .normal)

        if #available(macOS 11.0, *) {
            pipButton.setImage(UIImage(systemName: "pip.enter"), for: .normal)
            pipButton.setImage(UIImage(systemName: "pip.exit"), for: .selected)
            playButton.setImage(KSOptions.image(named: "playback.play"), for: .normal)
            playButton.setImage(KSOptions.image(named: "playback.pause"), for: .selected)
            srtButton.setImage(UIImage(systemName: "captions.bubble"), for: .normal)
            definitionButton.setImage(UIImage(systemName: "arrow.up.right.video"), for: .normal)
            audioSwitchButton.setImage(UIImage(systemName: "waveform"), for: .normal)
            videoSwitchButton.setImage(UIImage(systemName: "video.badge.ellipsis"), for: .normal)
            playbackRateButton.setImage(UIImage(systemName: "speedometer"), for: .normal)
        }

        srtButton.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        if #available(tvOS 14.0, *) {
            pipButton.isHidden = !AVPictureInPictureController.isPictureInPictureSupported()
        }

        playbackRateButton.tintColor = .white
        definitionButton.tintColor = .white
        audioSwitchButton.tintColor = .white
        videoSwitchButton.tintColor = .white
        srtButton.tintColor = .white
        pipButton.tintColor = .white
        extendedButton.tintColor = .white

    }

    public func addToContentView(_ view: UIView) {
        self.contentView.addSubview(view)
        view.isHidden = false
    }

    #if canImport(UIKit)
    override open func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if let nextFocusedItem = context.nextFocusedItem {
            if let nextFocusedButton = nextFocusedItem as? UIButton {
                nextFocusedButton.tintColor = nextFocusedButton.titleColor(for: .focused)
            }
            if context.previouslyFocusedItem != nil,
               let nextFocusedView = nextFocusedItem as? UIView
            {
                onFocusUpdate?(nextFocusedView)
            }
        }
        if let previouslyFocusedItem = context.previouslyFocusedItem as? UIButton {
            if previouslyFocusedItem.isSelected {
                previouslyFocusedItem.tintColor = previouslyFocusedItem.titleColor(for: .selected)
            } else if previouslyFocusedItem.isHighlighted {
                previouslyFocusedItem.tintColor = previouslyFocusedItem.titleColor(for: .highlighted)
            } else {
                previouslyFocusedItem.tintColor = previouslyFocusedItem.titleColor(for: .normal)
            }
        }
    }
    #endif

    open func addTarget(_ target: AnyObject?, action: Selector) {
        playButton.addTarget(target, action: action, for: .primaryActionTriggered)
        playbackRateButton.addTarget(target, action: action, for: .primaryActionTriggered)
        definitionButton.addTarget(target, action: action, for: .primaryActionTriggered)
        audioSwitchButton.addTarget(target, action: action, for: .primaryActionTriggered)
        videoSwitchButton.addTarget(target, action: action, for: .primaryActionTriggered)
        srtButton.addTarget(target, action: action, for: .primaryActionTriggered)
        pipButton.addTarget(target, action: action, for: .primaryActionTriggered)
        extendedButton.addTarget(target, action: action, for: .primaryActionTriggered)
    }

    public func reset() {
        currentTime = 0
        totalTime = 0
        playButton.isSelected = false
        timeSlider.value = 0.0
        timeSlider.isPlayable = false
        playbackRateButton.setTitle(NSLocalizedString("speed", comment: ""), for: .normal)
    }
}

extension KSOptions {
    static func image(named: String) -> UIImage? {
        #if canImport(UIKit)
        return UIImage(named: named, in: .module, compatibleWith: nil)
        #else
        return Bundle.module.image(forResource: named)
        #endif
    }
}
