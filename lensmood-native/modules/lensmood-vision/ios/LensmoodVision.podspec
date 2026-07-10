Pod::Spec.new do |s|
  s.name           = 'LensmoodVision'
  s.version        = '1.0.0'
  s.summary        = 'On-device Apple Vision recognition for LensMood'
  s.description    = 'Face detection and person segmentation via the Vision framework — feeds the develop engine, fully on-device.'
  s.author         = 'LensMood'
  s.homepage       = 'https://lensmood.app'
  s.license        = { :type => 'MIT' }
  s.platforms      = { :ios => '15.1' }
  s.source         = { :git => '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.source_files   = '**/*.{h,m,swift}'
end
