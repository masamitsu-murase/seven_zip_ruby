# SevenZipRuby

This is a Ruby gem library to handle [7-Zip](http://www.7-zip.org) archives.

This extension calls the native library, 7z.dll or 7z.so, internally and it is included in this gem.

## Features
* Use official DLL, 7z.dll, internally.
* Support multi-threaded execution.  

## Examples

**This is pre-alpha version.**  
The interfaces may be changed.

### Simple use

#### Extract archive
```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    szr.extract_all "path_to_dir"
  end
end
```

#### Show entries in archive
```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    list = szr.entries
    p list
    # => [ "[Dir: 0: dir/subdir]", "[File: 1: dir/file.txt]", ... ]
  end
end
```

#### Compress files
```ruby
File.open("filename.7z", "wb") do |file|
  SevenZipRuby::Writer.open(file) do |szr|
    szr.add_file "entry1.txt"
    szr.add_directory "dir1"
  end
end
```

```ruby
stream = StringIO.new("")
SevenZipRuby::Writer.open(stream) do |szr|
  szr.add_file "entry1.txt"
  szr.add_directory "dir1"
end
p stream.string
```

### More

#### Extract partially

Extract files whose size is less than 1024.

```ruby
File.open("filename.7z", "rb") do |file|
  SevenZipRuby::Reader.open(file) do |szr|
    small_files = szr.entries.select{ |i| i.file? && i.size < 1024 }
    szr.extract(small_files)
  end
end
```

