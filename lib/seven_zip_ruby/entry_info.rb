require("pathname")

module SevenZipRuby
  class EntryInfo
    def initialize(index, path, method, dir, encrypted, anti, size, pack_size, ctime, atime, mtime, attrib, crc)
      @index, @path, @method, @dir, @encrypted, @anti, @size, @pack_size, @ctime, @atime, @mtime, @attrib, @crc =
        index, Pathname(path.to_s.force_encoding(Encoding::UTF_8)).cleanpath.to_s, method, dir, encrypted, anti, size, pack_size, ctime, atime, mtime, attrib, crc
    end

    attr_reader :index, :path, :method, :size, :pack_size, :ctime, :atime, :mtime, :attrib, :crc
    alias to_i index
    alias crc32 crc

    def directory?
      return @dir
    end

    def file?
      return !(@dir)
    end

    def encrypted?
      return @encrypted
    end

    def anti?
      return @anti
    end

    def has_data?
      return !(@dir || @anti)
    end

    def inspect
      if (@anti)
        type = "anti"
      elsif (@dir)
        type = "dir"
      else
        type = "file"
      end
      str = path.encode(Encoding::ASCII, invalid: :replace, undef: :replace, replace: "?")
      return "#<EntryInfo: #{index}, #{type}, #{str}>"
    end
  end
end
