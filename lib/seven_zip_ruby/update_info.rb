module SevenZipRuby
  class UpdateInfo
    class << self
      def buffer(name, data, opt={})
        new(:buffer, opt.merge({ name: name, data: data }))
      end

      def dir(name, opt={})
        new(:dir, opt.merge({ name: name }))
      end

      def file(name, filepath, szw)
        new(:file, { name: name, filepath: filepath, szw: szw })
      end
    end

    def initialize(type, param)
      @type = type
      case(type)
      when :buffer
        name = param.delete(:name)
        data = param.delete(:data)
        initialize_buffer(name, data, param)
      when :dir
        name = param.delete(:name)
        initialize_dir(name, param)
      when :file
        initialize_file(param[:name], param[:filepath], param[:szw])
      end
    end

    def initialize_buffer(name, data, opt)
      @index_in_archive = nil
      @new_data = true
      @new_properties = true
      @anti = false

      @path = name
      @dir = false
      @data = data
      @size = data.size
      @attrib = 0x20
      @posix_attrib = 0x00
      time = Time.now
      @ctime = (opt[:ctime] || time)
      @atime = (opt[:atime] || time)
      @mtime = (opt[:mtime] || time)
      @user = @group = nil
    end

    def initialize_dir(name, opt)
      @index_in_archive = nil
      @new_data = true
      @new_properties = true
      @anti = false

      @path = name
      @dir = true
      @data = nil
      @size = 0
      @attrib = 0x10
      @posix_attrib = 0x00
      time = Time.now
      @ctime = (opt[:ctime] || time)
      @atime = (opt[:atime] || time)
      @mtime = (opt[:mtime] || time)
      @user = @group = nil
    end

    def initialize_file(name, filepath, szw)
      @index_in_archive = nil
      @new_data = true
      @new_properties = true
      @anti = false

      @path = name.to_s
      @dir = false
      filepath = Pathname(filepath).expand_path
      @data = filepath.to_s
      @size = filepath.size
      @attrib = (szw.get_file_attribute(filepath.to_s) || 0x20)
      @posix_attrib = 0x00
      @ctime = filepath.ctime
      @atime = filepath.atime
      @mtime = filepath.mtime
      @user = @group = nil
    end


    attr_reader :index_in_archive, :path, :data, :size, :attrib, :ctime, :atime, :mtime, :posix_attrib, :user, :group

    def buffer?
      return (@type == :buffer)
    end

    def directory?
      return @dir
    end

    def file?
      return !(@dir)
    end

    def new_data?
      return @new_data
    end

    def new_properties?
      return @new_properties
    end

    def anti?
      return @anti
    end
  end
end
