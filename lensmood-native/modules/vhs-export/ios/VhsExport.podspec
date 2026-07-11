Pod::Spec.new do |s|
  s.name           = 'VhsExport'
  s.version        = '1.0.0'
  s.summary        = 'LensMood camcorder video exporter'
  s.description    = 'Bakes the LensMood tape look (LUT, grain, vignette, timecode) into a video via AVFoundation.'
  s.author         = 'LensMood'
  s.homepage       = 'https://lensmood.app'
  s.license        = { :type => 'MIT' }
  s.platforms      = { :ios => '15.1' }
  s.source         = { :git => '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.source_files   = '**/*.{h,m,swift}'
end
