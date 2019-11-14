#!/bin/bash
# vim: tabstop=4 fileformat=unix fileencoding=utf-8 filetype=sh

tar_cmd="tar"
sevenzip_cmd="7z"

p7zip_ver="16.02"
p7zip_archive="p7zip_${p7zip_ver}_src_all.tar.bz2"
p7zip_debian_patch="p7zip_16.02+dfsg-7.debian.tar.xz"

sevenzip_archive="7z1900.exe"
sevenzip_archive_x64="7z1900-x64.exe"

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

	patch_debian "${dir_name}"

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

patch_debian() {
local dir_name=$1
local archive="$PWD/${p7zip_debian_patch}"
	if [[ "" == "${dir_name}" ]]
	then
		dir_name="p7zip"
	fi

	pushd "${dir_name}" > /dev/null

local work_dir="debian_patch"
local patch_dir="${work_dir}/debian/patches"
	mkdir "${work_dir}"
	cd "${work_dir}"
	tar --xz -xf "${archive}"
	cd ..

	cat "${patch_dir}/series" | while read ln
	do
		case "${ln}" in
		0[129]-* | 11-*)
			# ignore
			# 01-makefile.patch
			# 02-man.patch
			# 09-man-update.patch
			# 11-README-no-instructions.patch
			continue
			;;
		esac
		echo "INFO: patching ${ln}."
		patch -p 1 -i "${patch_dir}/${ln}"
	done

	rm -r "${work_dir}"

	popd > /dev/null
}

extract_7zip_dll() {
local work_dir="7zip_dll"
	mkdir "${work_dir}"
	pushd "${work_dir}" > /dev/null

	7z x ../"${sevenzip_archive_x64}" 7z.dll &&
	mv 7z.dll 7z64.dll

	7z x ../"${sevenzip_archive}" 7z.dll 7z.sfx 7zCon.sfx

local target_dir="../../lib/seven_zip_ruby/"
	mv * "${target_dir}"/.

	popd > /dev/null
	rmdir "${work_dir}"
}

basedir="`dirname "$0"`"
pushd "${basedir}" > /dev/null
#extract_lzma
extract_p7zip
#patch_debian
extract_7zip_dll
popd > /dev/null

