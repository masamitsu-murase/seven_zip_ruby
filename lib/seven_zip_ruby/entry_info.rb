require("pathname")

module SevenZipRuby
  class EntryInfo
    def initialize(index, path, method, dir, encrypted, anti, size, pack_size, ctime, atime, mtime, attrib, crc)
      @index, @path, @method, @dir, @encrypted, @anti, @size, @pack_size, @ctime, @atime, @mtime, @attrib, @crc =
        index, Pathname(path).cleanpath, method, dir, encrypted, anti, size, pack_size, ctime, atime, mtime, attrib, crc
    end

    attr_reader :index, :path, :method, :size, :pack_size, :ctime, :atime, :mtime, :attrib, :crc

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
        type = "Anti"
      elsif (@dir)
        type = "Dir"
      else
        type = "File"
      end
      return "[#{type}:#{index} :#{path}]"
    end
  end
end
