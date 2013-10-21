# SevenZipRuby

This is a Ruby gem library to handle [7-Zip](http://www.7-zip.org) archives.

This extension calls the native library, 7z.dll or 7z.so, internally and it is included in this gem.

## Features
* Use official DLL, 7z.dll, internally.
* Support multi-threaded execution.  

## Examples

*This is alpha version.*  
The interfaces may be changed.

### Simple use

#### Extract archive
```ruby
SevenZipRuby::Reader.open("filename.7z") do |szr|
  szr.extract :all, "path_to_dir"
end
```

#### Show entries in archive
```ruby
SevenZipRuby::Reader.open("filename.7z") do |szr|
  list = szr.entries
  p list
  # => [...]
end
```

#### Compress files
```ruby
SevenZipRuby::Writer.open("filename.7z") do |szr|
  szr.add_file "entry1.txt"
  szr.add_directory "dir1"
end
```

### More

#### Extract partially

```ruby
SevenZipRuby::Reader.open("filename.7z") do |szr|
  small_files = szr.entries.select{ |i| i.file? && i.size < 1024 }
  szr.extract(small_files)
end
```
