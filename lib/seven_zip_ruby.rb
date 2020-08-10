# -*- coding: utf-8 -*-

require("seven_zip_ruby/version")

module SevenZipRuby
  def self.find_external_lib_dir
    external_lib = (RUBY_PLATFORM.downcase.match(/mswin|mingw/) ? "7z.dll" : "7z.so")
    dir = $LOAD_PATH.find do |i|
      path = File.expand_path(File.join(i, "seven_zip_ruby", external_lib))
      next File.file?(path)
    end
    raise "Failed to find 7z.dll or 7z.so" unless dir

    return File.join(dir, "seven_zip_ruby")
  end

  EXTERNAL_LIB_DIR = self.find_external_lib_dir.encode(Encoding::UTF_8)
end

begin
  version = RUBY_VERSION.match(/\d+\.\d+/)
  require("seven_zip_ruby/#{version}/seven_zip_archive")
rescue LoadError
  require("seven_zip_ruby/seven_zip_archive")
end
raise "Failed to initialize SevenZipRuby" unless (defined?(SevenZipRuby::SevenZipReader))

require("seven_zip_ruby/seven_zip_reader")
require("seven_zip_ruby/seven_zip_writer")
require("seven_zip_ruby/archive_info")
require("seven_zip_ruby/update_info")
require("seven_zip_ruby/entry_info")
require("seven_zip_ruby/exception")

