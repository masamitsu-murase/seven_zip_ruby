# -*- coding: utf-8 -*-

require("mkmf")

if (RUBY_PLATFORM.include?("mswin"))
  $LIBS = "oleaut32.lib"
  $CPPFLAGS = "/I.. /EHsc"
elsif (RUBY_PLATFORM.include?("mingw"))
  # MinGW
  $LIBS = "-loleaut32 -static-libgcc -static-libstdc++"
  $CPPFLAGS = "-I.. -std=gnu++0x"
else
  # Linux
  Dir.chdir(File.expand_path("../../p7zip", __FILE__)) do
    make_success = system("make 7z")
    raise "Filed to make p7zip" unless (make_success)

    FileUtils.mv("./bin/7z.so", "../../lib/seven_zip_ruby/7z.so")
    system("make clean")
  end
  $LIBS = "-static-libgcc -static-libstdc++"
  $CPPFLAGS = "-I.. -I../CPP/include_windows -I../CPP -std=gnu++0x"
end

create_makefile("seven_zip_ruby/seven_zip_archive")

