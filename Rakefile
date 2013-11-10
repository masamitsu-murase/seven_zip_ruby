require "fileutils"
require "bundler/gem_tasks"

task :build_mingw32 => [ :pre_mingw32, :build, :post_mingw32 ] do
end

task :pre_mingw32 do
  FileUtils.mv("seven_zip_ruby.gemspec", "seven_zip_ruby.gemspec.bak")
  FileUtils.cp("resources/seven_zip_ruby.gemspec.x86-mingw32", "seven_zip_ruby.gemspec")
end

task :post_mingw32 do
  FileUtils.mv("seven_zip_ruby.gemspec.bak", "seven_zip_ruby.gemspec")
end

