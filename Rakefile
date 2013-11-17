require "fileutils"
require "bundler/gem_tasks"

task :build_platform => [ :pre_platform, :build, :post_platform ] do
end

task :pre_platform do
  FileUtils.mv("seven_zip_ruby.gemspec", "seven_zip_ruby.gemspec.bak")
  FileUtils.cp("resources/seven_zip_ruby.gemspec.platform", "seven_zip_ruby.gemspec")
end

task :post_platform do
  FileUtils.mv("seven_zip_ruby.gemspec.bak", "seven_zip_ruby.gemspec")
end

