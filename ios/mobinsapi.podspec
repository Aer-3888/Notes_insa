#
# Local pod that vendors the gomobile-built native data layer.
#
# The xcframework does NOT exist in a fresh checkout — it is generated on macOS
# by `scripts/ios_bootstrap.sh` (gomobile bind) into ios/Frameworks/ before
# `pod install` runs. Vendoring it through a pod lets CocoaPods handle linking
# and embedding so the Xcode project file (project.pbxproj) never needs manual
# edits.
#
# The Swift import name is `Mobinsapi` (the framework's own module), independent
# of this pod's name.
#
Pod::Spec.new do |s|
  s.name             = 'mobinsapi'
  s.version          = '1.0.0'
  s.summary          = 'Native Go data layer for Notes INSA (gomobile-built).'
  s.description      = 'gomobile-generated xcframework wrapping the INSA CAS / grades client.'
  s.homepage         = 'https://github.com/Aer-3888/Notes_insa'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Aer-3888' => 'theo.phan.quoc.huy@gmail.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.vendored_frameworks = 'Frameworks/Mobinsapi.xcframework'
end
