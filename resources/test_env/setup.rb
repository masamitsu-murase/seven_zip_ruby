
require("seven_zip_ruby")
require("ruby_installer_manager")
require("bundler")
require("pathname")
require("fileutils")

TMP_DIR = Pathname(__dir__) + "tmp"
SEVEN_ZIP_DIR = Pathname(__dir__).parent.parent

def run_with_devkit(devkitvars_bat, command)
  begin
    File.open("temp_bat.bat", "w") do |file|
      bat_path = devkitvars_bat.to_s.gsub('/'){ '\\' }
      file.puts "call \"#{bat_path}\""
      file.puts command
    end
    system("temp_bat.bat")
  ensure
    Pathname("temp_bat.bat").rmtree
  end
end

#================================================================
am = RubyInstallerManager::AutoManager.create(TMP_DIR)

# ruby_name_list_32 = [ "ruby2.3.3", "ruby2.2.6", "ruby2.1.9", "ruby2.0.0p648" ]
ruby_name_list_32 = [ "ruby2.3.3" ]
ruby_name_list_64 = ruby_name_list_32.map{ |i| i + "_64bit" }
ruby_name_list = ruby_name_list_32 + ruby_name_list_64

#================================================================
# Prepare and install
ruby_list = ruby_name_list.map do |ruby_name|
  puts ruby_name
  ruby = am.ruby_manager(ruby_name)
  ruby.prepare
  ruby.update_rubygems
  next ruby
end

devkit_list = ruby_list.map{ |r| am.devkit_for_ruby(r) }.uniq

devkit_list.each do |devkit|
  puts devkit.name
  devkit.prepare
  devkit.install(am.rubies_for_devkit(devkit).map(&:dir))
end

Dir.chdir(SEVEN_ZIP_DIR) do
  gemfile_lock = Pathname("Gemfile.lock")

  ruby_list.each do |ruby|
    puts ruby.name
    ruby.update_rubygems
    ruby.install_gem("bundler")
    ruby.ruby_env do
      begin
        gemfile_lock.rmtree if gemfile_lock.exist?
        system("bundle install")
        ruby.run_with_devkit("bundle exec rake build_local", am.devkit_for_ruby(ruby))
        system("bundle exec rspec spec/seven_zip_ruby_spec.rb")
      ensure
        ruby.run_with_devkit("bundle exec rake build_local_clean", am.devkit_for_ruby(ruby))
        gemfile_lock.rmtree if gemfile_lock.exist?
      end
    end
  end

  [ ruby_name_list_32, ruby_name_list_64 ].each do |name_list|
    bin_list = {}
    list = ruby_list.select{ |i| name_list.include?(i.name) }
    next if list.empty?

    list.each do |ruby|
      ver = ruby.name.match(/^ruby([0-9]+\.[0-9]+)/)[1]
      ruby.ruby_env do
        begin
          ruby.run_with_devkit("bundle exec rake build_local", am.devkit_for_ruby(ruby))
          bin_list[ver] = File.open("ext/seven_zip_ruby/seven_zip_archive.so", "rb", &:read)
        ensure
          ruby.run_with_devkit("bundle exec rake build_local_clean", am.devkit_for_ruby(ruby))
          gemfile_lock.rmtree if gemfile_lock.exist?
        end
      end
    end

    bin_list.each do |ver, bin|
      dir = "lib/seven_zip_ruby/#{ver}"
      FileUtils.mkpath(dir)
      File.open("#{dir}/seven_zip_archive.so", "wb") do |file|
        file.write(bin)
      end
    end

    ruby = list.first
    ruby.ruby_env do
      begin
        ruby.run_with_devkit("bundle exec rake build_platform", am.devkit_for_ruby(ruby))
      ensure
        gemfile_lock.rmtree if gemfile_lock.exist?
      end
    end

    bin_list.each do |ver, bin|
      dir = "lib/seven_zip_ruby/#{ver}"
      FileUtils.rmtree(dir)
    end

    ruby.ruby_env do
      begin
        system("bundle exec rake build")
      ensure
        gemfile_lock.rmtree if gemfile_lock.exist?
      end
    end
  end
end


