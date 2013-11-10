# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'seven_zip_ruby/version'

Gem::Specification.new do |spec|
  spec.name          = "seven_zip_ruby"
  spec.version       = SevenZipRuby::VERSION
  spec.authors       = ["Masamitsu MURASE"]
  spec.email         = ["masamitsu.murase@gmail.com"]
  spec.description   = %q{SevenZipRuby is a gem library to read and write 7zip archives. This gem library calls official 7z.dll internally.}
  spec.summary       = %q{This is a gem library to read and write 7-Zip files.}
  spec.homepage      = "https://github.com/masamitsu-murase/seven_zip_ruby"
  spec.license       = "LGPL + unRAR"

  spec.files         = `git ls-files`.split($/).select{ |i| !(i.start_with?("pkg") || i.start_with?("resources")) }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"

  spec.extensions << "ext/seven_zip_ruby/extconf.rb"
end
