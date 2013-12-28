
require("fileutils")
require("net/http")
require("uri")
require("seven_zip_ruby")
require("zlib")
require("archive/tar/minitar")

BASE_DIR = File.expand_path("../../../..", __FILE__)
COMPLETE_FILE = "complete.txt"

def log(str)
  puts str
end

def my_system(str)
  ret = system(str)
  raise "system error #{str}" unless (ret)
end

def download(url)
  log("Download #{url}...")
  url = URI.parse(url)
  res = Net::HTTP.start(url.host, url.port) do |http|
    http.get(url.request_uri)
  end
  log("  Done.")
  return res.body
end

def normalize_dir(dir)
  entries = Dir.entries(dir).select{ |i| i != ".." && i != "." }
  if (entries.size == 1)
    FileUtils.mv(File.join(dir, entries[0]), "hoge")
    FileUtils.rmdir(dir)
    FileUtils.mv("hoge", dir)
  end
end

def extract(data, dir)
  log("Extract to #{dir}...")
  io = StringIO.new(data)
  SevenZipRuby::SevenZipReader.open(io) do |szr|
    szr.extract_all(dir)
  end
  normalize_dir(dir)
  log("  Done.")
end

def extract_tar_gz(data, dir)
  log("Extract tar.gz to #{dir}")
  tgz = Zlib::GzipReader.new(StringIO.new(data))
  Archive::Tar::Minitar.unpack(tgz, dir)
  normalize_dir(dir)
  log("  Done.")
end

def register_devkit(ruby_dir, devkit_dir)
  ruby_dir = File.expand_path(ruby_dir)
  Dir.chdir(devkit_dir) do
    File.open("config.yml", "w") do |file|
      str = <<"EOS"
---
- #{ruby_dir}
EOS
      file.puts(str)
    end

    log("Register devkit...")
    my_system("\"#{File.join(ruby_dir, 'bin', 'ruby.exe')}\" dk.rb install")
    log("  Done")
  end
end

def setup_mingw(dir, ruby_url, devkit_url)
  dir = File.expand_path(dir, BASE_DIR)

  complete_file = File.expand_path(COMPLETE_FILE, dir)
  if (File.exist?(complete_file))
    log("MinGW #{dir} is found in local.")
    return
  end

  begin
    FileUtils.rmtree(dir) if (File.exist?(dir))

    FileUtils.mkpath(dir)

    Dir.chdir(dir) do
      ruby_dir = "ruby"
      devkit_dir = "devkit"

      data = download(ruby_url)
      extract(data, ruby_dir)

      data = download(devkit_url)
      extract(data, devkit_dir)

      register_devkit(ruby_dir, devkit_dir)

      FileUtils.touch(COMPLETE_FILE)
    end
  rescue => e
    log(e.inspect)
  end
end

def setup_vc2010(dir, ruby_url, vcvars_path)
  dir = File.expand_path(dir, BASE_DIR)

  complete_file = File.expand_path(COMPLETE_FILE, dir)
  if (File.exist?(complete_file))
    log("VC2010 #{dir} is found in local.")
    return
  end

  begin
    FileUtils.rmtree(dir) if (File.exist?(dir))

    FileUtils.mkpath(dir)

    Dir.chdir(dir) do
      ruby_src_dir = "ruby_src"
      ruby_dir = "ruby"

      data = download(ruby_url)
      extract_tar_gz(data, ruby_src_dir)

      File.open("build_ruby.bat", "w") do |file|
        str = <<"EOS"
call "#{vcvars_path}"
cd /d "#{File.join(dir, ruby_src_dir)}"
md build
cd build
call ..\\win32\\configure.bat --prefix=#{File.join(dir, ruby_dir)}
nmake
nmake install
EOS
        file.puts(str)
      end
      my_system("build_ruby.bat")

      FileUtils.rmtree(ruby_src_dir)

      FileUtils.touch(COMPLETE_FILE)
    end
  rescue => e
    log(e.inspect)
  end
end


################################################################
# The following setting should be customized by each user.
def init_env_var
  lib = [ "C:\\OpenSSL-Win32\\lib", "D:\\my_program\\GnuWin32\\lib" ]
  lib.push(ENV["LIB"]) if (ENV["LIB"])
  ENV["LIB"] = lib.join(";")

  include = [ "C:\\OpenSSL-Win32\\include", "D:\\my_program\\GnuWin32\\include" ]
  include.push(ENV["INCLUDE"]) if (ENV["INCLUDE"])
  ENV["INCLUDE"] = include.join(";")

  path = [ "D:\\my_program\\GnuWin32\\bin", "D:\\my_program\\git\\bin" ]
  path.push(ENV["PATH"]) if (ENV["PATH"])
  ENV["PATH"] = path.join(";")
end


init_env_var

setup_mingw("mingw32",
      "http://dl.bintray.com/oneclick/rubyinstaller/ruby-2.0.0-p353-i386-mingw32.7z?direct",
      "http://cdn.rubyinstaller.org/archives/devkits/DevKit-mingw64-32-4.7.2-20130224-1151-sfx.exe")
setup_mingw("mingw32_64",
      "http://dl.bintray.com/oneclick/rubyinstaller/ruby-2.0.0-p353-x64-mingw32.7z?direct",
      "http://cdn.rubyinstaller.org/archives/devkits/DevKit-mingw64-64-4.7.2-20130224-1432-sfx.exe")
setup_vc2010("vc2010",
      "http://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.0.tar.gz",
      "C:\\Program Files (x86)\\Microsoft Visual Studio 10.0\\VC\\bin\\vcvars32.bat")

