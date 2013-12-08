# -*- coding: utf-8 -*-

require("seven_zip_ruby/version")

external_lib = [ "7z.so", "7z.dll" ]
dir = $:.find do |i|
  next external_lib.any?{ |so| File.file?(File.join(i, "seven_zip_ruby", so)) }
end
raise "Failed to find 7z.dll or 7z.so" unless (dir)

Dir.chdir(File.join(dir, "seven_zip_ruby"))do
  require("seven_zip_ruby/seven_zip_archive")
end
raise "Failed to initialize SevenZipRuby" unless (defined?(SevenZipRuby::SevenZipReader))

require("seven_zip_ruby/seven_zip_reader")
require("seven_zip_ruby/seven_zip_writer")
require("seven_zip_ruby/archive_info")
require("seven_zip_ruby/update_info")
require("seven_zip_ruby/entry_info")
require("seven_zip_ruby/exception")

module SevenZipRuby
end
