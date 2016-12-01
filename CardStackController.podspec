Pod::Spec.new do |s|

  s.name         = "CardStackController"
  s.version      = "0.1.0"
  s.summary      = "Custom controller that presents new ViewControllers as cards. Used in Jobandtalent iOS app"

  s.description  = <<-DESC
  CardStackController
  iOS custom controller used in the Jobandtalent app to present new view controllers as cards.
  DESC

  s.homepage     = "https://github.com/jobandtalent/CardStackController"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { 'Victor Baro' => 'fs.baro@gmail.com' }
  s.source       = { :git => "https://github.com/jobandtalent/CardStackController.git", :tag => "#{s.version}" }
  s.ios.deployment_target = '8.0'
  s.source_files = 'CardStackController/Classes/**/*'
end
