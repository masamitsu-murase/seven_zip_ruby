# -*- coding: utf-8 -*-

require("seven_zip_ruby/version")

external_lib = (RUBY_PLATFORM.downcase.match(/mswin|mingw/) ? "7z.dll" : "7z.so")
dir = $:.find do |i|
  next File.file?(File.join(i, "seven_zip_ruby", external_lib))
end
raise "Failed to find 7z.dll or 7z.so" unless (dir)

Dir.chdir(File.join(dir, "seven_zip_ruby"))do
  begin
    version = RUBY_VERSION.match(/\d+\.\d+/)
    require("seven_zip_ruby/#{version}/seven_zip_archive")
  rescue LoadError
    require("seven_zip_ruby/seven_zip_archive")
  end
end
raise "Failed to initialize SevenZipRuby" unless (defined?(SevenZipRuby::SevenZipReader))

require("seven_zip_ruby/seven_zip_reader")
require("seven_zip_ruby/seven_zip_writer")
require("seven_zip_ruby/archive_info")
require("seven_zip_ruby/update_info")
require("seven_zip_ruby/entry_info")
require("seven_zip_ruby/exception")

