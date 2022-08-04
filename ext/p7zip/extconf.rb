# -*- coding: utf-8 -*-

require("mkmf")
require("rbconfig")

SO_TARGET_DIR = File.expand_path(File.join(RbConfig::CONFIG["sitearchdir"], "seven_zip_ruby"))

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

def dummy_makefile
  return <<'EOS'
all: dummy
.PHONY: all dummy install
install:
dummy:
EOS
end

def real_makefile
  mf = <<'EOS'
.PHONY: all 7zso clean

all: 7zso

7zso:
	mkdir -p bin
	$(MAKE) -C CPP/7zip/Bundles/Format7zFree all

clean:
	$(MAKE) -C CPP/7zip/Bundles/Format7zFree clean
	rm -fr bin

install:
EOS
  dest = File.expand_path(File.join(File.dirname(__FILE__), "../../lib/seven_zip_ruby"))
  mf += "\tcp bin/7z.so #{dest}\n"
  return mf
end

def main
  if (RUBY_PLATFORM.include?("mswin") || RUBY_PLATFORM.include?("mingw"))
    mfile = open("Makefile", "wb")
    mfile.puts dummy_makefile
    mfile.close
  else
    ostype = check_ostype
    create_p7zip_makefile(ostype)
    MakeMakefile.rm_f "makefile"
    mfile = open("Makefile", "w")
    mfile.puts real_makefile
    mfile.close
  end
end

main
