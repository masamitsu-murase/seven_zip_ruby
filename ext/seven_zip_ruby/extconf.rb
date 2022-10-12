# -*- coding: utf-8 -*-

require("mkmf")
require("rbconfig")

def sample_cpp_source
  # Check the following features.
  #  - lambda
  #  - std::function
  #  - std::array
  #  - memset_s defined, on Darwin and BSD
  return <<'EOS'
#include <functional>
#include <algorithm>
#include <array>
#include <iostream>

#include <ruby.h>

// see the test on memset_s below, which is a purely BSD thing
#if defined(__APPLE__) || defined(BSD)
#include <string.h>
#endif

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

#if defined(__APPLE__) || defined(BSD)
    char str[] = "imareallycoolstringright";
    memset_s(str, sizeof str, 'b', 5);
#endif
}
EOS
end

def sample_for_rb_thread_call_without_gvl(have_ruby_thread_h)
  header = "#include <ruby.h>\n"
  header += "#include <ruby/thread.h>\n" if (have_ruby_thread_h)
  body = <<'EOS'

#include <stdio.h>

int main(int argc, char *argv[])
{
    printf("%p\n", rb_thread_call_without_gvl);
    return 0;
}
EOS
  return header + body
end

def sample_for_nullptr
  return <<'EOS'
#include <stdio.h>
int main(int argc, char *argv[])
{
    printf("%p\n", nullptr);
    return 0;
}
EOS
end

def main
  base_flag = ""

  th_h = have_header("ruby/thread.h")

  unless (try_compile(sample_for_rb_thread_call_without_gvl(th_h)))
    base_flag += " -DNO_RB_THREAD_CALL_WITHOUT_GVL"
  end
  unless (try_compile(sample_for_nullptr))
    base_flag += " -DNO_NULLPTR"
  end

  if (RUBY_PLATFORM.include?("mswin"))
    # mswin32
    $LIBS = "oleaut32.lib shlwapi.lib"
    $CPPFLAGS = "/I.. /EHsc /DNDEBUG /DUSE_WIN32_FILE_API #{base_flag} #{$CPPFLAGS} "
  elsif (RUBY_PLATFORM.include?("mingw"))
    # MinGW
    $LIBS = "-loleaut32 -lshlwapi -static-libgcc -static-libstdc++"

    cpp0x_flag = [ "", "-std=gnu++11", "-std=c++11", "-std=gnu++0x", "-std=c++0x" ].find do |opt|
      try_compile(sample_cpp_source, "#{opt} -x c++ ")
    end
    raise "C++11 is not supported by the compiler." unless (cpp0x_flag)

    $CPPFLAGS = "-I.. #{cpp0x_flag} -DNDEBUG -DUSE_WIN32_FILE_API #{base_flag} #{$CPPFLAGS} "
  else
    removed_flags = [ /\-mmacosx\-version\-min=[.0-9]+\b/ ]
    removed_flags.each do |flag|
      begin
        $CFLAGS[flag] = ""
      rescue
      end
    end

    possible_cpp0x_flags = [ "", "-std=gnu++11", "-std=c++11", "-std=gnu++0x", "-std=c++0x" ].map do |opt|
      ["#{opt} -x c++ ", "#{opt} "]
    end.flatten
    cpp0x_flag = possible_cpp0x_flags.find do |opt|
      try_compile(sample_cpp_source, opt)
    end
    raise "C++11 is not supported by the compiler." unless (cpp0x_flag)

    $CPPFLAGS = "-I.. -I../CPP/include_windows -I../CPP #{cpp0x_flag} -DNDEBUG #{base_flag} #{$CPPFLAGS} "

  end
  mfile = create_makefile("seven_zip_ruby/seven_zip_archive")
end

main
