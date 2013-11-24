require("stringio")

module SevenZipRuby
  class SevenZipWriter
    PATH_ENCODING = Encoding::UTF_8

    class << self
      def open(stream, param = {}, &block)
        szw = self.new
        szw.open(stream, param)
        if (block)
          block.call(szw)
          szw.compress
          szw.close
        else
          szw
        end
      end
    end

    def open(stream, param = {})
      stream.set_encoding(Encoding::ASCII_8BIT)
      open_impl(stream, param)
      return self
    end

    def compress
      compress_impl(compress_proc)
      return self
    end

    def add_file(filename)
      path = Pathname(filename)
      raise ArgumentError.new("filename should be relative") if (path.absolute?)

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      add_item(UpdateInfo.file(name, name, self))
      return self
    end

    def add_buffer(filename, data, opt={})
      path = Pathname(filename)
      raise ArgumentError.new("filename should be relative") if (path.absolute?)
      check_option(opt, [ :ctime, :atime, :mtime ])

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      add_item(UpdateInfo.buffer(name, data, opt))
      return self
    end

    def add_directory(directory)
      directory = Pathname(directory).cleanpath
      raise ArgumentError.new("directory should be relative") if (directory.absolute?)

      mkdir(directory, { ctime: directory.ctime, atime: directory.atime, mtime: directory.mtime })

      Pathname.glob(directory.join("**").to_s) do |entry|
        if (entry.file?)
          add_file(entry)
        elsif (entry.directory?)
          mkdir(entry, { ctime: entry.ctime, atime: entry.atime, mtime: entry.mtime })
        else
          raise "#{entry} is invalid entry"
        end
      end

      return self
    end
    alias add_dir add_directory

    def mkdir(directory_name, opt={})
      path = Pathname(directory_name)
      raise ArgumentError.new("directory_name should be relative") if (path.absolute?)
      check_option(opt, [ :ctime, :atime, :mtime ])

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      add_item(UpdateInfo.dir(name, opt))
      return self
    end


    def check_option(opt, keys)
      invalid_keys = opt.keys - keys
      raise ArgumentError.new("invalid option: " + invalid_keys.join(", ")) unless (invalid_keys.empty?)
    end


    def compress_proc
      return Proc.new do |type, info|
        case(type)
        when :stream
          if (info.buffer?)
            next StringIO.new(info.data)
          elsif (info.file?)
            next File.open(info.data, "rb")
          else
            next nil
          end
        when :result
          info[:stream].close if (info[:stream])
        end
      end
    end
    private :compress_proc
  end


  Writer = SevenZipWriter
end
