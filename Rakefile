require "fileutils"
require "tempfile"
require "bundler/gem_tasks"

BINARY_FILES = [ "seven_zip_archive.so", "seven_zip_archive.bundle" ]
MAKE = (ENV["MAKE"] || ENV["make"] || (RUBY_PLATFORM.include?("mswin") ? "nmake" : "make"))

task :build_platform => [ :pre_platform, :build, :post_platform ]

task :pre_platform do
  FileUtils.mv("seven_zip_ruby.gemspec", "seven_zip_ruby.gemspec.bak")
  FileUtils.cp("resources/seven_zip_ruby.gemspec.platform", "seven_zip_ruby.gemspec")
end

task :post_platform do
  FileUtils.mv("seven_zip_ruby.gemspec.bak", "seven_zip_ruby.gemspec")
end


task :build_local_all => [ :build_local_clean, :build_local ]
task :build_local => [ :build_binary, :copy_binary ]

task :build_local_clean do
  Dir.chdir "ext/seven_zip_ruby" do
    sh("#{MAKE} clean") if (File.exist?("Makefile"))
  end

  [ "ext/seven_zip_ruby", "lib/seven_zip_ruby" ].each do |dir|
    FileUtils.rmtree(BINARY_FILES.map{ |i| "#{dir}/#{i}" })
  end
end

task :build_binary do
  Dir.chdir "ext/seven_zip_ruby" do
    FileUtils.rmtree BINARY_FILES

    Tempfile.open([ "site", ".rb" ], Dir.pwd) do |temp|
      temp.puts <<"EOS"
require('rbconfig')
RbConfig::CONFIG['sitearchdir'] = "../../lib"
EOS
      temp.flush

      sh "ruby -r#{File.expand_path(temp.path)} extconf.rb"
      temp.unlink
    end

    sh "#{MAKE}"
  end
end

task :copy_binary do
  BINARY_FILES.each do |file|
    src = File.join("ext", "seven_zip_ruby", file)
    dest = File.join("lib", "seven_zip_ruby", file)
    FileUtils.rmtree(dest) if (File.exist?(dest))
    FileUtils.cp(src, dest) if (File.exist?(src))
  end
end
