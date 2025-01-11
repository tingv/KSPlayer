//
//  AudioPlayerView.swift
//  VoiceNote
//
//  Created by kintan on 2018/8/16.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
open class AudioPlayerView: PlayerView {
    override public init(frame: CGRect) {
        super.init(frame: frame)
        toolBar.timeType = .min
        toolBar.addToContentView(toolBar.playButton)
        toolBar.addToContentView(toolBar.currentTimeLabel)
        toolBar.addToContentView(toolBar.timeSlider)
        toolBar.addToContentView(toolBar.totalTimeLabel)
        toolBar.playButton.tintColor = UIColor(rgb: 0x2166FF)
        toolBar.timeSlider.setThumbImage(UIColor(rgb: 0x2980FF).createImage(size: CGSize(width: 2, height: 15)), for: .normal)
        toolBar.timeSlider.minimumTrackTintColor = UIColor(rgb: 0xC8C7CC)
        toolBar.timeSlider.maximumTrackTintColor = UIColor(rgb: 0xEDEDED)
        toolBar.timeSlider.trackHeigt = 7
        addSubview(toolBar)
        toolBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            toolBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            toolBar.topAnchor.constraint(equalTo: topAnchor),
            toolBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
