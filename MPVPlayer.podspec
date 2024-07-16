Pod::Spec.new do |s|
    s.name             = 'MPVPlayer'
    s.version          = '1.1.0'
    s.summary          = 'Video Player Using Swift, based on AVPlayer,FFmpeg'

    s.description      = <<-DESC
    Video Player Using Swift, based on ffmpeg, support for the horizontal screen, vertical screen, the upper and lower slide to adjust the volume, the screen brightness, or so slide to adjust the playback progress.
    DESC

    s.homepage         = 'https://github.com/kingslay/KSPlayer'
    s.authors = { 'kintan' => 'kingslay@icloud.com' }
    s.license          = 'MIT'
    s.source           = { :git => 'https://github.com/kingslay/KSPlayer.git', :tag => s.version.to_s }

    s.ios.deployment_target = '13.0'
    s.osx.deployment_target = '10.15'
    # s.watchos.deployment_target = '2.0'
    s.tvos.deployment_target = '13.0'
    s.static_framework = true
    s.subspec 'MPVPlayer' do |ss|
        ss.source_files = 'Sources/MPVPlayer/*.{swift}'
        ss.dependency 'KSPlayer'
        ss.dependency 'Libmpv'
    end  
end
