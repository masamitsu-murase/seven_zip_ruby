# SevenZipRuby ![Logo](https://raw.github.com/masamitsu-murase/seven_zip_ruby/master/resources/seven_zip_ruby_logo.png)

This is a Ruby gem library to handle [7-Zip](http://www.7-zip.org) archives.

This extension calls the native library, 7z.dll or 7z.so, internally and it is included in this gem.

## Features
* Use official DLL, 7z.dll, internally.
* Support extracting data into memory.

## Examples

**This is a beta version.**  
The interfaces may be changed.

If you have any comments about interface API, let me know please.

### Extract archive
```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    szr.extract_all "path_to_dir"
  end
end
```

### Show entries in archive
```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    list = szr.entries
    p list
    # => [ "[Dir: 0: dir/subdir]", "[File: 1: dir/file.txt]", ... ]
  end
end
```

### Extract encrypted archive
```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file, { password: "Password String" }) do |szr|
    szr.extract_all "path_to_dir"
  end
end
```

### Verify archive
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
    szr.add_file "entry1.txt"
    szr.mkdir "dir1"
    szr.add_buffer "entry2.txt", "binary_data 123456"
  end
end
```

```ruby
stream = StringIO.new("")
SevenZipRuby::Writer.open(stream) do |szr|
  szr.add_file "entry1.txt"
  szr.mkdir "dir1"
end
p stream.string
```

## Supported platforms

* Windows
* Linux (partially tested)

Mac OSX will be supported in the later version.

## More examples

### Extract partially

Extract files whose size is less than 1024.

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    small_files = szr.entries.select{ |i| i.file? && i.size < 1024 }
    szr.extract(small_files)
  end
end
```

### Get data from archive

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
#  => "File content. ...."
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
  szr.multi_thread = true  # Enable multi-threading mode (default)
  szr.add_buffer("test.bin", data)
end
p(Time.now - start)
#  => 3.607563

a = StringIO.new("")
start = Time.now
SevenZipRuby::Writer.open(a) do |szr|
  szr.method = "BZIP2"     # Set compression method to "BZIP2"
  szr.multi_thread = false # Disable multi-threading mode
  szr.add_buffer("test.bin", data)
end
p(Time.now - start)
#  => 11.180934  # Slower than multi-threaded compression.
```


## TODO

* Support file attributes correctly.
* Support convenient methods.
* Support Mac and Linux.
* Support updating archive.
* Support extracting rar archive.


## License
LGPL and unRAR license. Please refer to LICENSE.txt.

