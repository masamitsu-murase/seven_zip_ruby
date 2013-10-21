# -*- coding: utf-8 -*-

require_relative("seven_zip_ruby/version")

Dir.chdir("#{__dir__}/seven_zip_ruby"){ require_relative("seven_zip_ruby/seven_zip_archive") }

require_relative("seven_zip_ruby/seven_zip_reader")
require_relative("seven_zip_ruby/seven_zip_writer")
require_relative("seven_zip_ruby/archive_info")
require_relative("seven_zip_ruby/update_info")
require_relative("seven_zip_ruby/entry_info")
require_relative("seven_zip_ruby/exception")

module SevenZipRuby
end
