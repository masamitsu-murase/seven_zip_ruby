# SevenZipRuby ![Logo](https://raw.github.com/fontist/seven_zip_ruby/master/resources/seven_zip_ruby_logo.png)

![RSpec](https://github.com/fontist/seven_zip_ruby/workflows/test-and-release/badge.svg) [![Gem Version](https://badge.fury.io/rb/seven-zip.png)](http://badge.fury.io/rb/seven-zip)

This is a Ruby gem library to extract/compress [7-Zip](http://www.7-zip.org) archives.

This extension calls the native library, 7z.dll or 7z.so, internally and these libraries are included in this gem.

## Features
* Uses official shared library, 7z.dll or 7z.so, internally.
* Supports extracting data into memory.

## Document
[RDoc](http://rubydoc.info/gems/seven-zip/frames) shows you the details.

## Examples

### Extract archives

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    szr.extract_all "path_to_dir"
  end
end
```

You can also use simpler method.

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.extract_all(file, "path_to_dir")
end
```

### Show the entries in the archive

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    list = szr.entries
    p list
    # => [ "#<EntryInfo: 0, dir, dir/subdir>", "#<EntryInfo: 1, file, dir/file.txt>", ... ]
  end
end
```

### Extract encrypted archives

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file, { password: "Password String" }) do |szr|
    szr.extract_all "path_to_dir"
  end
end
```
or

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.extract_all(file, "path_to_dir", { password: "Password String" })
end
```


### Verify archives

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.verify(file)
  # => true/false
end
```

### Compress files

```ruby
File.open("filename.7z", "wb") do |file|
  SevenZipRuby::Writer.open(file) do |szr|
    szr.add_directory("dir")
  end
end
```
or

```ruby
File.open("filename.7z", "wb") do |file|
  SevenZipRuby::Writer.add_directory(file, "dir")
end
```

## Supported environment

SevenZipRuby supports the following platforms.

* Windows
* Linux
* Mac OSX

SevenZipRuby supports the following Ruby engines on each platform.

* MRI 2.3.0 and later

## More examples

### Extract partially

Extract files whose size is less than 1024.

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    small_files = szr.entries.select{ |i| i.file? && i.size < 1024 }
    szr.extract(small_files, "path_to_dir")
  end
end
```

### Get data from archives

Extract data into memory.

```ruby
data = nil
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    smallest_file = szr.entries.select(&:file?).min_by(&:size)
    data = szr.extract_data(smallest_file)
  end
end
p data
#  => File content is shown.
```

### Create an archive manually

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Writer.open(file) do |szr|
    szr.add_file "entry1.txt"
    szr.mkdir "dir1"
    szr.mkdir "dir2"

    data = [0, 1, 2, 3, 4].pack("C*")
    szr.add_data data, "entry2.txt"
  end
end
```

You can also create a self extracting archive for Windows.

```ruby
File.open("filename.exe", "rb") do |file|
  # :gui and :console can be specified as :sfx parameter.
  SevenZipRuby::Writer.open(file, sfx: :gui) do |szr|
    szr.add_data "file content", "file.txt"
  end
end
```

### Set compression mode

7zip supports LZMA, LZMA2, PPMD, BZIP2, DEFLATE and COPY.

```ruby
# random data
data = 50000000.to_enum(:times).map{ rand(256) }.pack("C*")

a = StringIO.new("")
start = Time.now
SevenZipRuby::Writer.open(a) do |szr|
  szr.method = "BZIP2"     # Set compression method to "BZIP2"
  szr.multi_thread = false # Disable multi-threading mode
  szr.add_data(data, "test.bin")
end
p(Time.now - start)
#  => 11.180934

a = StringIO.new("")
start = Time.now
SevenZipRuby::Writer.open(a) do |szr|
  szr.method = "BZIP2"     # Set compression method to "BZIP2"
  szr.multi_thread = true  # Enable multi-threading mode (default)
  szr.add_data(data, "test.bin")
end
p(Time.now - start)
#  => 3.607563    # Faster than single-threaded compression.
```

## License
LGPL license. Please refer to LICENSE.txt.

## Releases
* 1.4.2
  - CI improvement, cleanup of debug output
* 1.4.1
  - Fixed minor rubygems.org issues
* 1.4.0
  - seven-zip gem forked from seven_zip_ruby
  - Fixed C++17 compatibility (https://github.com/masamitsu-murase/seven_zip_ruby/issues/36).
  - 7z.so (p7zip module) converted to Ruby extension in order to facilitate Ruby 3.0 compatiblity.
* 1.3.0
* 1.2.*
  - Fixed cosmetic bugs.
* 1.1.0
  - Fixed a bug. Raises an exception when wrong password is specified.
* 1.0.0
  - Initial release.
