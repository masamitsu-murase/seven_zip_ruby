require("stringio")

module SevenZipRuby
  class SevenZipWriter
    PATH_ENCODING = Encoding::UTF_8

    class << self
      def open(stream, param = {}, &block)
        szw = self.new
        szw.open(stream, param)
        if (block)
          begin
            block.call(szw)
            szw.compress
          ensure
            szw.close
          end
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

    def add_buffer(filename, data)
      path = Pathname(filename)
      raise ArgumentError.new("filename should be relative") if (path.absolute?)

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      data = data.b
      add_item(UpdateInfo.buffer(name, data))
      return self
    end

    def add_directory(directory_name)
      path = Pathname(directory_name)
      raise ArgumentError.new("directory_name should be relative") if (path.absolute?)

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      add_item(UpdateInfo.dir(name))
      return self
    end


    def compress_proc
      return Proc.new do |type, info|
        case(type)
        when :stream
          if (info.buffer?)
            next StringIO.new(info.data)
          elsif (info.file?)
            # TODO
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
