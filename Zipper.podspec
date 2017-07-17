Pod::Spec.new do |s|
  s.name = 'Zipper'
  s.version = '1.0.2'
  s.license = 'MIT'
  s.summary = 'Effortless ZIP Handling in Swift'
  s.homepage = 'https://github.com/Meniny/Zipper'
  s.social_media_url = 'http://meniny.cn/'
  s.authors = { 'Elias Abel' => 'Meniny@qq.com' }
  s.source = { :git => 'https://github.com/Meniny/Zipper.git', :tag => s.version }

  s.ios.deployment_target = '9.0'
  s.osx.deployment_target = '10.11'
  s.tvos.deployment_target = '9.0'
  s.watchos.deployment_target = '2.0'

  s.source_files = 'Zipper/Source/*'
  s.public_header_files = 'Zipper/Source/*.h'

end
