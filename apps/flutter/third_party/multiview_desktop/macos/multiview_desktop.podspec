Pod::Spec.new do |s|
  s.name             = 'multiview_desktop'
  s.version          = '1.0.0'
  s.summary          = 'Single-engine multi-window Flutter desktop library.'
  s.description      = <<-DESC
Single-engine multi-window Flutter desktop library based on ViewCollection.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'multiview_desktop/Sources/multiview_desktop/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
