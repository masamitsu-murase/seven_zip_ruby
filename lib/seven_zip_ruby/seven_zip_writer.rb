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

      def add_directory(stream, dir, param = {})
        password = { password: param.delete(:password) }
        self.open(stream, password) do |szw|
          szw.add_directory(dir, param)
        end
      end
      alias add_dir add_directory

      def add_file(stream, filename, param = {})
        password = { password: param.delete(:password) }
        self.open(stream, password) do |szw|
          szw.add_file(filename, param)
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

    def add_file(filename, opt={})
      path = Pathname(filename)
      check_option(opt, [ :as ])

      if (opt[:as])
        filename = Pathname(opt[:as]).cleanpath
        raise ArgumentError.new(":as should contain valid pathname. #{opt[:as]}") if (filename.to_s.empty?)
        raise ArgumentError.new(":as should be relative. #{opt[:as]}") if (filename.absolute?)
      else
        raise ArgumentError.new("filename should be relative. #{filename}") if (path.absolute?)
        filename = path.cleanpath
      end
      add_item(UpdateInfo.file(filename.to_s.encode(PATH_ENCODING), path, self))
      return self
    end

    def add_data(data, filename, opt={})
      path = Pathname(filename)
      raise ArgumentError.new("filename should be relative") if (path.absolute?)
      check_option(opt, [ :ctime, :atime, :mtime ])

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      add_item(UpdateInfo.buffer(name, data, opt))
      return self
    end

    def add_directory(directory, opt={})
      directory = Pathname(directory).cleanpath
      check_option(opt, [ :as ])

      if (opt[:as])
        base_dir = Pathname(opt[:as]).cleanpath
        raise ArgumentError.new(":as should contain valid pathname. #{opt[:as]}") if (base_dir.to_s.empty?)
        raise ArgumentError.new(":as should be relative. #{opt[:as]}") if (base_dir.absolute?)

        mkdir(base_dir, { ctime: directory.ctime, atime: directory.atime, mtime: directory.mtime })
      else
        raise ArgumentError.new("directory should be relative #{directory}") if (directory.absolute?)

        mkdir(directory, { ctime: directory.ctime, atime: directory.atime, mtime: directory.mtime })
      end

      Pathname.glob(directory.join("**", "*").to_s) do |entry|
        name = (base_dir + entry.relative_path_from(directory)).cleanpath if (base_dir)

        if (entry.file?)
          add_file(entry, as: name)
        elsif (entry.directory?)
          mkdir(name || entry, { ctime: entry.ctime, atime: entry.atime, mtime: entry.mtime })
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
