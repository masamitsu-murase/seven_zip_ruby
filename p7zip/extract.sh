#!/bin/bash
# vim: tabstop=4 fileformat=unix fileencoding=utf-8 filetype=sh

tar_cmd="tar"
sevenzip_cmd="7z"

p7zip_ver="16.02"
p7zip_archive="p7zip_${p7zip_ver}_src_all.tar.bz2"


extract_p7zip() {
local dir_name="p7zip"
	tar -jxf "${p7zip_archive}" \
		--exclude Asm \
		--exclude CPP/7zip/Bundles/Alone \
		--exclude CPP/7zip/Bundles/Alone7z \
		--exclude CPP/7zip/Bundles/AloneGCOV \
		--exclude CPP/7zip/Bundles/LzmaCon \
		--exclude CPP/7zip/Bundles/SFXCon \
		--exclude CPP/7zip/CMAKE \
		--exclude CPP/7zip/PREMAKE \
		--exclude CPP/7zip/Q7Zip \
		--exclude CPP/7zip/QMAKE \
		--exclude CPP/7zip/TEST \
		--exclude CPP/7zip/UI \
		--exclude CPP/ANDROID \
		--exclude CPP/Windows/Control \
		--exclude GUI \
		--exclude Utils \
		--exclude check \
		--exclude contrib \
		--exclude man1
	mv "p7zip_${p7zip_ver}" "${dir_name}"

	rm "${dir_name}"/CPP/myWindows/initguid.h
	rm "${dir_name}"/CPP/myWindows/makefile*
	rm "${dir_name}"/CPP/myWindows/myAddExeFlag.cpp
	rm "${dir_name}"/CPP/myWindows/mySplitCommandLine.cpp
	rm "${dir_name}"/CPP/myWindows/test_lib.cpp
	rm "${dir_name}"/CPP/myWindows/wine_GetXXXDefaultLangID.cpp

	rm "${dir_name}"/CPP/Windows/ErrorMsg.*
	rm "${dir_name}"/CPP/Windows/PropVariantConv.*
	rm "${dir_name}"/CPP/Windows/*.back
	rm "${dir_name}"/CPP/Windows/Registry.*
	rm "${dir_name}"/CPP/Windows/COM.*
	rm "${dir_name}"/CPP/Windows/Clipboard.*
	rm "${dir_name}"/CPP/Windows/DLL.*
	rm "${dir_name}"/CPP/Windows/Window.*
	rm "${dir_name}"/CPP/Windows/CommonDialog.h
	rm "${dir_name}"/CPP/Windows/Menu.h
	rm "${dir_name}"/CPP/Windows/ResourceString.h
	rm "${dir_name}"/CPP/Windows/Shell.h

	sed -i "${dir_name}"/makefile.machine \
		-e 's/^\(CXX=g++\|CC=gcc\)$/\1  $(ALLFLAGS)/'

local target_dir="../ext"
	if [[ -e "${target_dir}/${dir_name}" ]]
	then
		echo "WARR: ${target_dir}/${dir_name} is exist. Cannot move automatically."
	else
		mv "${dir_name}" "${target_dir}"/.
	fi
}

basedir="`dirname "$0"`"
pushd "${basedir}" > /dev/null
#extract_lzma
extract_p7zip
popd > /dev/null

