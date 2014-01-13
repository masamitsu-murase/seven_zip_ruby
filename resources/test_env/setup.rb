
require("fileutils")
require("net/http")
require("net/ftp")
require("uri")
require("seven_zip_ruby")
require("zlib")
require("archive/tar/minitar")
require("tempfile")

BASE_DIR = File.expand_path("../../../..", __FILE__)
SEVEN_ZIP_DIR = File.expand_path("../../..", __FILE__)
COMPLETE_FILE = "complete.txt"

def log(str)
  puts str
end

class RubyEnv
  class << self
    def init_env_var
      lib = [ "C:\\OpenSSL-Win32\\lib", "D:\\my_program\\GnuWin32\\lib" ]
      lib.push(ENV["LIB"]) if (ENV["LIB"])
      ENV["LIB"] = lib.join(";")

      include = [ "C:\\OpenSSL-Win32\\include", "D:\\my_program\\GnuWin32\\include" ]
      include.push(ENV["INCLUDE"]) if (ENV["INCLUDE"])
      ENV["INCLUDE"] = include.join(";")

      path = [ "C:\\Program Files\\7-Zip", "D:\\my_program\\GnuWin32\\bin", "D:\\my_program\\git\\bin" ]
      path.push(ENV["PATH"]) if (ENV["PATH"])
      ENV["PATH"] = path.join(";")
    end
  end

  def initialize(dir)
    @dir = dir
    @ruby_dir = File.expand_path(File.join(dir, "ruby"), BASE_DIR)
  end

  def download(url)
    log("Download #{url}...")
    url = URI.parse(url)
    case(url.scheme)
    when "http"
      res = Net::HTTP.start(url.host, url.port) do |http|
        http.get(url.request_uri)
      end
      data = res.body
    when "ftp"
      tempfilename = "hoge.tar.gz"
      Net::FTP.open(url.host) do |ftp|
        ftp.login
        ftp.passive = true
        ftp.getbinaryfile(url.path, tempfilename, 1024)
      end
      data = File.open(tempfilename, "rb", &:read)
      FileUtils.rmtree(tempfilename)
    end
    log("  Done.")
    return data
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

  def set_path(path, &block)
    path = Array(path)
    old_path = ENV["PATH"]
    begin
      ENV["PATH"] = path.map{ |i| i.gsub("/"){ "\\" } }.join(";") + ";#{old_path}"
      block.call
    ensure
      ENV["PATH"] = old_path
    end
  end

  def gem_env(gem_dir, &block)
    set_path(File.join(@ruby_dir, "bin")) do
      old_make = ENV["MAKE"]
      begin
        ENV["MAKE"] = make_command

        Dir.chdir(gem_dir) do
          block.call
        end
      ensure
        ENV["MAKE"] = old_make
      end
    end
  end

  def my_system(str)
    ret = system(str)
    raise "system error #{str}" unless (ret)
  end

  def my_system_with_precommand(str)
    Tempfile.open([ "temp", ".bat" ], Dir.pwd) do |temp|
      temp.puts("@echo off")
      temp.puts(@precommand) if (@precommand)
      temp.puts(str)
      temp.close
      ret = system(File.basename(temp.path))
      temp.close!
      raise "system error #{str}" unless (ret)
    end
  end

  def bundler_install
    gem_env(SEVEN_ZIP_DIR) do
      FileUtils.rmtree("Gemfile.lock") if (File.exist?("Gemfile.lock"))

      log("Install bundler...")
      my_system_with_precommand("gem install bundler --no-rdoc --no-ri")
      log("  Done")
      log("Bundle install...")
      my_system_with_precommand("bundle install --jobs=4")
      log("  Done")
    end
  end

  def rake(rake_command)
    gem_env(SEVEN_ZIP_DIR) do
      FileUtils.rmtree("Gemfile.lock") if (File.exist?("Gemfile.lock"))

      log("Rake #{rake_command}...")
      my_system_with_precommand("bundle exec rake #{rake_command}")
      log("  Done")
    end
  end

  def rspec
    gem_env(SEVEN_ZIP_DIR) do
      FileUtils.rmtree("Gemfile.lock") if (File.exist?("Gemfile.lock"))

      log("Rspec spec/seven_zip_ruby_spec.rb")
      my_system_with_precommand("bundle exec rspec spec/seven_zip_ruby_spec.rb")
      log("  Done")
    end
  end
end

class RubyEnvMinGW < RubyEnv
  def initialize(dir, ruby_url, devkit_url)
    super(dir)
    @ruby_url = ruby_url
    @devkit_url = devkit_url

    @devkit_dir = File.expand_path(File.join(@dir, "devkit"), BASE_DIR)
    @precommand = "call \"#{File.join(@devkit_dir, 'devkitvars.bat')}\""
  end

  def make_command
    return "make"
  end

  def setup
    setup_mingw(@dir, @ruby_url, @devkit_url)
  end

  def register_devkit(devkit_dir)
    Dir.chdir(devkit_dir) do
      File.open("config.yml", "w") do |file|
        str = <<"EOS"
---
- #{@ruby_dir}
EOS
        file.puts(str)
      end

      log("Register devkit...")
      my_system("\"#{File.join(@ruby_dir, 'bin', 'ruby.exe')}\" dk.rb install")
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

    FileUtils.rmtree(dir) if (File.exist?(dir))

    FileUtils.mkpath(dir)

    Dir.chdir(dir) do
      data = download(ruby_url)
      extract(data, @ruby_dir)

      data = download(devkit_url)
      extract(data, @devkit_dir)

      register_devkit(@devkit_dir)

      bundler_install

      FileUtils.touch(COMPLETE_FILE)
    end
  end
end

class RubyEnvVC2010 < RubyEnv
  def initialize(dir, ruby_url, vcvars_path)
    super(dir)
    @ruby_url = ruby_url
    @vcvars_path = vcvars_path

    @precommand = "call \"#{vcvars_path}\""
  end

  def make_command
    return "nmake"
  end

  def setup
    setup_vc2010(@dir, @ruby_url, @vcvars_path)
  end

  def setup_vc2010(dir, ruby_url, vcvars_path)
    dir = File.expand_path(dir, BASE_DIR)

    complete_file = File.expand_path(COMPLETE_FILE, dir)
    if (File.exist?(complete_file))
      log("VC2010 #{dir} is found in local.")
      return
    end

    FileUtils.rmtree(dir) if (File.exist?(dir))

    FileUtils.mkpath(dir)

    Dir.chdir(dir) do
      ruby_src_dir = "ruby_src"

      data = download(ruby_url)
      extract_tar_gz(data, ruby_src_dir)

      File.open("build_ruby.bat", "w") do |file|
        str = <<"EOS"
call "#{vcvars_path}"
cd /d "#{File.join(dir, ruby_src_dir)}"
md build
cd build
call ..\\win32\\configure.bat --prefix=#{@ruby_dir}
nmake
nmake install
EOS
        file.puts(str)
      end
      my_system("build_ruby.bat")

#      FileUtils.rmtree(ruby_src_dir)

      bundler_install

      FileUtils.touch(COMPLETE_FILE)
    end
  end
end



RubyEnv.init_env_var

ruby_env_list = []

ruby200_mingw32 =
  RubyEnvMinGW.new("ruby200/mingw32",
               "http://dl.bintray.com/oneclick/rubyinstaller/ruby-2.0.0-p353-i386-mingw32.7z?direct",
               "http://cdn.rubyinstaller.org/archives/devkits/DevKit-mingw64-32-4.7.2-20130224-1151-sfx.exe")
ruby_env_list.push({
                     "2.0" => ruby200_mingw32
                   })

ruby200_mingw32_64 =
  RubyEnvMinGW.new("ruby200/mingw32_64",
               "http://dl.bintray.com/oneclick/rubyinstaller/ruby-2.0.0-p353-x64-mingw32.7z?direct",
               "http://cdn.rubyinstaller.org/archives/devkits/DevKit-mingw64-64-4.7.2-20130224-1432-sfx.exe")
ruby_env_list.push({
                     "2.0" => ruby200_mingw32_64
                   })

ruby200_vc2010 =
  RubyEnvVC2010.new("ruby200/vc2010",
                "ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p247.tar.gz",
                "C:\\Program Files (x86)\\Microsoft Visual Studio 10.0\\VC\\bin\\vcvars32.bat")
ruby210_vc2010 =
  RubyEnvVC2010.new("ruby210/vc2010",
                "http://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.0.tar.gz",
                "C:\\Program Files (x86)\\Microsoft Visual Studio 10.0\\VC\\bin\\vcvars32.bat")
ruby_env_list.push({
                     "2.0" => ruby200_vc2010,
                     "2.1" => ruby210_vc2010
                   })

ruby_env_list.map(&:values).flatten.each do |ruby|
  ruby.setup
end

# Test
ruby_env_list.map(&:values).flatten.each do |ruby|
  begin
    ruby.rake("build_local")
    ruby.rspec
  ensure
    ruby.rake("build_local_clean")
  end
end

# Create platform-specific gem.
ruby_env_list.each do |ruby_vers|
  bin_list = {}
  ruby_vers.each do |ver, ruby|
    begin
      ruby.rake("build_local")
      Dir.chdir(SEVEN_ZIP_DIR) do
        bin_list[ver] = File.open("ext/seven_zip_ruby/seven_zip_archive.so", "rb", &:read)
      end
    ensure
      ruby.rake("build_local_clean")
    end
  end
  Dir.chdir(SEVEN_ZIP_DIR) do
    bin_list.each do |ver, bin|
      dir = "lib/seven_zip_ruby/#{ver}"
      FileUtils.mkpath(dir)
      File.open("#{dir}/seven_zip_archive.so", "wb") do |file|
        file.write(bin)
      end
    end
    ruby_vers.first[1].rake("build_platform")

    bin_list.each do |ver, bin|
      dir = "lib/seven_zip_ruby/#{ver}"
      FileUtils.rmtree(dir)
    end
  end
end

# Create normal gem.
ret = system("rake build")
raise "rake build error" unless (ret)

