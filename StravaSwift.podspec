Pod::Spec.new do |s|
  s.name             = 'StravaSwift'
  s.version          = '1.0.2'
  s.summary          = 'A Swift library for the Strava API v3'
  s.description      = <<-DESC
A Swift library for the Strava API v3. For complete details visit the Strava developer site.
                       DESC
  s.homepage         = 'https://github.com/aikynetix/StravaSwift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Matthew Clarkson' => 'mpclarkson@gmail.com' }
  s.source           = { :git => 'https://github.com/aikynetix/StravaSwift.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/matt_pc'
  s.swift_version    = '5.0'
  s.ios.deployment_target = '15.0'
  s.source_files = 'Sources/StravaSwift/**/*'
  s.dependency 'Alamofire', '~> 5'
  s.dependency 'SwiftyJSON', '~> 5'
end
