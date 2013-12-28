# -*- coding: utf-8 -*-

require("fileutils")
require("rbconfig")

module SevenZipRubySpecHelper
  DETAIL_CHECK = true

  BASE_DIR = File.expand_path("..", __FILE__)
  TEMP_DIR = File.expand_path("../../tmp", __FILE__)

  SAMPLE_FILE_DIR_RELATIVE = "sample_file"
  SAMPLE_FILE_DIR = File.expand_path(SAMPLE_FILE_DIR_RELATIVE, TEMP_DIR)

  EXTRACT_DIR_RELATIVE = "extract"
  EXTRACT_DIR = File.expand_path(EXTRACT_DIR_RELATIVE, TEMP_DIR)

  SAMPLE_DATA = [
    { name: "ascii_file.txt", data: "ASCII Files", directory: false },
    { name: "empty_file.txt", data: "", directory: false },
    { name: "directory", directory: true },
    { name: "directory/utf8_file.txt", data: "日本語のファイル".force_encoding("ASCII-8BIT"), directory: false },
    { name: "directory/utf8_name®.txt", data: "日本語のファイル".force_encoding("ASCII-8BIT"), directory: false },
    { name: "directory/.dot.txt", data: "Dot text".force_encoding("ASCII-8BIT"), directory: false },
    { name: "directory/.dot_dir", directory: true },
    { name: "directory/.dot_dir/normal.txt", data: "Dot text".force_encoding("ASCII-8BIT"), directory: false },
    { name: ".dot_dir", directory: true },
    { name: ".dot_dir/normal.txt", data: "Normal text".force_encoding("ASCII-8BIT"), directory: false },
    { name: ".dot_dir/.dot.txt", data: "Dot text".force_encoding("ASCII-8BIT"), directory: false },
    { name: "empty_directory", directory: true }
  ]

  SAMPLE_LARGE_RANDOM_DATA = (0...100000).to_a.pack("L*")
  SAMPLE_LARGE_RANDOM_DATA_TIMESTAMP = Time.utc(2013, 10, 22)

  SEVEN_ZIP_FILE = File.expand_path("seven_zip.7z", TEMP_DIR)
  SEVEN_ZIP_PASSWORD_FILE = File.expand_path("seven_zip_password.7z", TEMP_DIR)
  SEVEN_ZIP_PASSWORD = "123 456"


  class << self
    def my_system(str)
      `#{str}`
      raise "System failed: #{str}" unless ($?.exitstatus == 0)
    end


    def prepare_each
      cleanup_each
    end

    def cleanup_each
      FileUtils.rmtree(EXTRACT_DIR) if (File.exist?(EXTRACT_DIR))
    end


    def prepare_all
      cleanup_all

      prepare_sample_file
      prepare_seven_zip_file
    end

    def prepare_sample_file
      FileUtils.mkpath(SAMPLE_FILE_DIR)
      Dir.chdir(SAMPLE_FILE_DIR) do
        SAMPLE_DATA.each do |item|
          if (item[:directory])
            FileUtils.mkpath(item[:name])
          else
            File.open(item[:name], "wb"){ |file| file.write(item[:data]) }
          end
        end
      end
    end

    def prepare_seven_zip_file
      Dir.chdir(SAMPLE_FILE_DIR) do
        files = (Dir.glob("*", File::FNM_DOTMATCH).to_a - [ ".", ".." ]).join(" ")
        my_system("7z a -bd \"#{SEVEN_ZIP_FILE}\" #{files}")
        my_system("7z a -bd \"-p#{SEVEN_ZIP_PASSWORD}\" \"#{SEVEN_ZIP_PASSWORD_FILE}\" #{files}")
      end
    end


    def cleanup_all
      cleanup_seven_zip_file
      cleanup_sample_file
    end

    def cleanup_sample_file
      FileUtils.rmtree(SAMPLE_FILE_DIR) if (File.exist?(SAMPLE_FILE_DIR))
    end

    def cleanup_seven_zip_file
      FileUtils.rmtree(SEVEN_ZIP_FILE) if (File.exist?(SEVEN_ZIP_FILE))
      FileUtils.rmtree(SEVEN_ZIP_PASSWORD_FILE) if (File.exist?(SEVEN_ZIP_PASSWORD_FILE))
    end


    def processor_count
      return @processor_count unless (@processor_count.nil?)

      if (RbConfig::CONFIG["target_os"].match(/mingw|mswin/))
        # Windows
        require("win32ole")
        @processor_count = WIN32OLE.connect("winmgmts://")
          .ExecQuery("SELECT NumberOfLogicalProcessors from Win32_Processor")
          .to_enum(:each).map(&:NumberOfLogicalProcessors).reduce(:+)
      elsif (File.exist?("/proc/cpuinfo"))
        # Linux
        @processor_count = File.open("/proc/cpuinfo", &:read).scan(/^processor/).size
      elsif (RbConfig::CONFIG["target_os"].include?("darwin"))
        # Mac
        begin
          @processor_count = `sysctl hw.ncpu`.split(":").last.to_i
        rescue
          @processor_count = false
        end
      else
        # Unknown
        @processor_count = false
      end

      return @processor_count
    end
  end
end

