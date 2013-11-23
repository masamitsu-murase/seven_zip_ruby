# -*- coding: utf-8 -*-

require("mkmf")
require("rbconfig")


def create_p7zip_makefile(type)
  config = RbConfig::CONFIG

  allflags = config["ARCH_FLAG"] + ' -O -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -D_REENTRANT -DENV_UNIX '
  case(type)
  when :macosx
    allflags += ' -DENV_MACOSX '
    cc_shared = nil
    link_shared = "-bundle"
    local_libs = "-framework CoreFoundation"
    local_libs_dll = '$(LOCAL_LIBS)'
  when :linux
    allflags += ' -DNDEBUG -D_7ZIP_LARGE_PAGES -pipe -s '
    cc_shared = "-fPIC"
    link_shared = "-fPIC -shared"
    local_libs = "-lpthread"
    local_libs_dll = '$(LOCAL_LIBS) -ldl'
  end

  cc_shared_content = (cc_shared ? "CC_SHARED=#{cc_shared}" : "")

  makefile_content = <<"EOS"
ALLFLAGS=#{allflags} $(LOCAL_FLAGS)
CXX=#{config['CXX']} $(ALLFLAGS)
CC=#{config['CC']} $(ALLFLAGS)
#{cc_shared_content}
LINK_SHARED=#{link_shared}

LOCAL_LIBS=#{local_libs}
LOCAL_LIBS_DLL=#{local_libs_dll}
OBJ_CRC32=$(OBJ_CRC32_C)
EOS

  File.open("makefile.machine", "w") do |file|
    file.puts makefile_content
  end
end

def check_ostype
  if (RUBY_PLATFORM.include?("darwin"))
    return :macosx
  elsif (RUBY_PLATFORM.include?("linux"))
    return :linux
  else
    raise "Unsupported platform"
  end
end

def sample_cpp_source
  # Check the following features.
  #  - lambda
  #  - std::function
  #  - std::array
  return <<'EOS'
#include <functional>
#include <algorithm>
#include <array>
#include <iostream>

#include <ruby.h>
#include <ruby/thread.h>

void test()
{
    int array[] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const int size = sizeof(array)/sizeof(array[0]);
    std::array<int, size> var_list;

    std::function<int (int, int)> convert = [&](int arg1, int arg2){
        return arg1 * arg2;
    };

    const int value = 10;

    std::transform(array, array + size, var_list.begin(), [&](int arg){
        return convert(arg, value);
    });

    std::for_each(var_list.begin(), var_list.end(), [](int num){ std::cout << num << std::endl; });
}
EOS
end

def main
  if (RUBY_PLATFORM.include?("mswin"))
    # mswin32
    $LIBS = "oleaut32.lib"
    $CPPFLAGS = "/I.. /EHsc /DNDEBUG"
  elsif (RUBY_PLATFORM.include?("mingw"))
    # MinGW
    $LIBS = "-loleaut32 -static-libgcc -static-libstdc++"

    cpp0x_flag = [ "", "-std=c++11", "-std=gnu++11", "-std=c++0x", "-std=gnu++0x" ].find do |opt|
      next try_compile(sample_cpp_source, "#{opt} -x c++ ")
    end
    raise "C++11 is not supported by the compiler." unless (cpp0x_flag)

    $CPPFLAGS = "-I.. #{cpp0x_flag} -DNDEBUG "
  else
    cpp0x_flag = [ "", "-std=c++11", "-std=gnu++11", "-std=c++0x", "-std=gnu++0x" ].find do |opt|
      next (try_compile(sample_cpp_source, "#{opt} -x c++ ") || try_compile(sample_cpp_source, "#{opt} "))
    end
    raise "C++11 is not supported by the compiler." unless (cpp0x_flag)

    $CPPFLAGS = "-I.. -I../CPP/include_windows -I../CPP #{cpp0x_flag} -DNDEBUG "


    ostype = check_ostype

    Dir.chdir(File.expand_path("../../p7zip", __FILE__)) do
      create_p7zip_makefile(ostype)

      make_success = system("make 7zso")
      raise "Failed to make p7zip" unless (make_success)

      FileUtils.mv("./bin/7z.so", "../../lib/seven_zip_ruby/7z.so")
      system("make clean")
    end
  end

  create_makefile("seven_zip_ruby/seven_zip_archive")
end

main

