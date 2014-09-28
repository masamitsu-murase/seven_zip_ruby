require("stringio")
require("thread")

module SevenZipRuby

  # SevenZipWriter creates 7zip archive.
  #
  # == Properties
  # +method+ :: Compression method. "LZMA", "LZMA2", "PPMd", "BZIP2", "DEFLATE" or "COPY". Default value is "LZMA".
  # +level+ :: Compression level. 0, 1, 3, 5, 7 or 9. Default value is 5.
  # +solid+ :: Solid compression. <tt>true</tt> or <tt>false</tt>. Default value is <tt>true</tt>.
  # +header_compression+ :: Header compression. <tt>true</tt> or <tt>false</tt>. Default value is <tt>true</tt>.
  # +header_encryption+ :: Header encryption. <tt>true</tt> or <tt>false</tt>. Default value is <tt>false</tt>.
  # +multi_threading+ :: Multi threading. <tt>true</tt> or <tt>false</tt>. Default value is <tt>true</tt>.
  #
  # == Examples
  # === Compress files
  #   # Compress files
  #   File.open("filename.7z", "wb") do |file|
  #     SevenZipRuby::SevenZipWriter.open(file) do |szw|
  #       szw.add_directory("test_dir")
  #       szw.add_file("test.txt")
  #     end
  #   end
  #
  #   # Compress files 2
  #   SevenZipRuby::SevenZipWriter.open_file("filename.7z") do |szw|
  #     szw.add_directory("test_dir")
  #     Dir.chdir("parent_dir_of_test.txt") do
  #       szw.add_file("test.txt")
  #     end
  #   end
  #
  #   stream = StringIO.new("")
  #   SevenZipRuby::SevenZipWriter.open(stream) do |szw|
  #     szw.add_file("test.txt")
  #     szw.add_data(data, "test.bin")
  #   end
  #   # p stream.string
  #
  # === Set various properties
  #   File.open("filename.7z", "wb") do |file|
  #     SevenZipRuby::SevenZipWriter.open(file, password: "Password") do |szw|
  #       szw.method = "LZMA"
  #       szw.level = 9
  #       szw.solid = false
  #       szw.header_compression = false
  #       szw.header_encryption = true
  #       szw.multi_threading = false
  #
  #       szw.add_directory("test_dir")
  #     end
  #   end
  #
  # === Create a sfx, a self extracting archive for Windows executable binary.
  #   File.open("filename.exe", "wb") do |file|
  #     SevenZipRuby::SevenZipWriter.open(file, sfx: true) do |szw|
  #       szw.add_directory("test_dir")
  #     end
  #   end
  class SevenZipWriter
    # Encoding used for path string in 7zip archive.
    PATH_ENCODING = Encoding::UTF_8

    # Files for self extraction.
    SFX_FILE_LIST = {
      default: File.expand_path("../7z.sfx", __FILE__),
      gui:     File.expand_path("../7z.sfx", __FILE__),
      console: File.expand_path("../7zCon.sfx", __FILE__)
    }  # :nodoc:

    OPEN_PARAM_LIST = [ :password, :sfx ]  # :nodoc:

    @use_native_input_file_stream = true

    class << self
      attr_accessor :use_native_input_file_stream

      # Open 7zip archive to write.
      #
      # ==== Args
      # +stream+ :: Output stream to write 7zip archive. <tt>stream.write</tt> is needed.
      # +param+ :: Optional hash parameter.  
      #            <tt>:password</tt> key specifies password of this archive.  
      #            <tt>:sfx</tt> key specifies Self Extracting mode. <tt>:gui</tt> and <tt>:console</tt> can be used. <tt>true</tt> is same as <tt>:gui</tt>.
      #
      # ==== Examples
      #   # Open an archive
      #   File.open("filename.7z", "wb") do |file|
      #     SevenZipRuby::SevenZipWriter.open(file) do |szw|
      #       # Create archive.
      #       # ...
      #       # You don't have to call szw.compress. Of cource, you may call it.
      #       # szw.compress
      #     end
      #   end
      #
      #   # Open without block.
      #   File.open("filename.7z", "wb") do |file|
      #     szw = SevenZipRuby::SevenZipWriter.open(file)
      #     # Create archive.
      #     szw.compress  # Compress must be called in this case.
      #     szw.close
      #   end
      #
      #   # Create a self extracting archive. <tt>:gui</tt> and <tt>:console</tt> can be used.
      #   File.open("filename.7z", "wb") do |file|
      #     szw = SevenZipRuby::SevenZipWriter.open(file, sfx: :gui)
      #     # Create archive.
      #     szw.compress  # Compress must be called in this case.
      #     szw.close
      #   end
      def open(stream, param = {}, &block)  # :yield: szw
        szw = self.new
        szw.open(stream, param)
        if (block)
          begin
            block.call(szw)
            szw.compress
            szw.close
          ensure
            szw.close_file
          end
        else
          szw
        end
      end

      # Open 7zip archive file.
      #
      # ==== Args
      # +filename+ :: 7zip archive filename.
      # +param+ :: Optional hash parameter.  
      #            <tt>:password</tt> key specifies password of this archive.  
      #            <tt>:sfx</tt> key specifies Self Extracting mode. <tt>:gui</tt> and <tt>:console</tt> can be used. <tt>true</tt> is same as <tt>:gui</tt>.
      #
      # ==== Examples
      #   # Open archive
      #   SevenZipRuby::SevenZipWriter.open_file("filename.7z") do |szw|
      #     # Create archive.
      #     # ...
      #     # You don't have to call szw.compress. Of cource, you may call it.
      #     # szw.compress
      #   end
      #
      #   # Open without block.
      #   szw = SevenZipRuby::SevenZipWriter.open_file("filename.7z")
      #   # Create archive.
      #   szw.compress  # Compress must be called in this case.
      #   szw.close
      def open_file(filename, param = {}, &block)  # :yield: szw
        szw = self.new
        szw.open_file(filename, param)
        if (block)
          begin
            block.call(szw)
            szw.compress
            szw.close
          ensure
            szw.close_file
          end
        else
          szw
        end
      end

      # Create 7zip archive which includes the specified directory recursively.
      #
      # ==== Args
      # +stream+ :: Output stream to write 7zip archive. <tt>stream.write</tt> is needed.
      # +dir+ :: Directory to be added to the 7zip archive. <b><tt>dir</tt></b> must be a <b>relative path</b>.
      # +param+ :: Optional hash parameter.  
      #            <tt>:password</tt> key specifies password of this archive.  
      #            <tt>:sfx</tt> key specifies Self Extracting mode. <tt>:gui</tt> and <tt>:console</tt> can be used. <tt>true</tt> is same as <tt>:gui</tt>.
      #
      # ==== Examples
      #   # Create 7zip archive which includes 'dir'.
      #   File.open("filename.7z", "wb") do |file|
      #     SevenZipRuby::SevenZipWriter.add_directory(file, 'dir')
      #   end
      def add_directory(stream, dir, param = {})
        param = param.clone
        open_param = {}
        OPEN_PARAM_LIST.each do |key|
          open_param[key] = param.delete(key) if param.key?(key)
        end
        self.open(stream, open_param) do |szw|
          szw.add_directory(dir, param)
        end
      end
      alias add_dir add_directory  # +add_dir+ is an alias of +add_directory+.

      # Create 7zip archive which includes the specified file recursively.
      #
      # ==== Args
      # +stream+ :: Output stream to write 7zip archive. <tt>stream.write</tt> is needed.
      # +file+ :: File to be added to the 7zip archive. <b><tt>file</tt></b> must be a <b>relative path</b>.
      # +param+ :: Optional hash parameter.  
      #            <tt>:password</tt> key specifies password of this archive.  
      #            <tt>:sfx</tt> key specifies Self Extracting mode. <tt>:gui</tt> and <tt>:console</tt> can be used. <tt>true</tt> is same as <tt>:gui</tt>.
      #
      # ==== Examples
      #   # Create 7zip archive which includes 'file.txt'.
      #   File.open("filename.7z", "wb") do |file|
      #     SevenZipRuby::SevenZipWriter.add_file(file, 'file.txt')
      #   end
      def add_file(stream, filename, param = {})
        param = param.clone
        open_param = {}
        OPEN_PARAM_LIST.each do |key|
          open_param[key] = param.delete(key) if param.key?(key)
        end
        self.open(stream, open_param) do |szw|
          szw.add_file(filename, param)
        end
      end
    end

    undef initialize_copy, clone, dup

    # Open 7zip archive to create.
    #
    # ==== Args
    # +stream+ :: Output stream to write 7zip archive. <tt>stream.write</tt> is needed.
    # +param+ :: Optional hash parameter.  
    #            <tt>:password</tt> key specifies password of this archive.  
    #            <tt>:sfx</tt> key specifies Self Extracting mode. <tt>:gui</tt> and <tt>:console</tt> can be used. <tt>true</tt> is same as <tt>:gui</tt>.
    #
    # ==== Examples
    #   File.open("filename.7z", "wb") do |file|
    #     szw = SevenZipRuby::SevenZipWriter.new
    #     szw.open(file)
    #     # ...
    #     szw.compress
    #     szw.close
    #   end
    def open(stream, param = {})
      param = param.clone
      param[:password] = param[:password].to_s if (param[:password])
      stream.set_encoding(Encoding::ASCII_8BIT)

      add_sfx(stream, param[:sfx]) if param[:sfx]

      open_impl(stream, param)
      return self
    end

    # Open 7zip archive file to create.
    #
    # <tt>close</tt> method must be called later.
    #
    # ==== Args
    # +filename+ :: 7zip archive filename.
    # +param+ :: Optional hash parameter.  
    #            <tt>:password</tt> key specifies password of this archive.  
    #            <tt>:sfx</tt> key specifies Self Extracting mode. <tt>:gui</tt> and <tt>:console</tt> can be used. <tt>true</tt> is same as <tt>:gui</tt>.
    #
    # ==== Examples
    #   szw = SevenZipRuby::SevenZipWriter.new
    #   szw.open_file("filename.7z")
    #   # ...
    #   szw.compress
    #   szw.close
    def open_file(filename, param = {})
      @stream = File.open(filename, "wb")
      self.open(@stream, param)
      return self
    end

    def close
      close_impl
      close_file
    end

    def close_file  # :nodoc:
      if (@stream)
        @stream.close rescue nil
        @stream = nil
      end
    end

    # Compress and output data to archive file.
    # You don't have to call this method when you use block-style SevenZipWriter.open.
    #
    # ==== Examples
    #  # Open archive
    #  File.open("filename.7z", "wb") do |file|
    #    SevenZipRuby::SevenZipWriter.open(file) do |szw|
    #      # Create archive.
    #      # ...
    #      # You don't have to call szw.compress. Of cource, you may call it.
    #      # szw.compress
    #    end
    #  end
    #
    #  # Open without block.
    #  File.open("filename.7z", "wb") do |file|
    #    szw = SevenZipRuby::SevenZipWriter.open(file)
    #    # Create archive.
    #    szw.compress  # Compress must be called in this case.
    #    szw.close
    #  end
    def compress
      synchronize do
        compress_impl(compress_proc)
      end
      return self
    end

    # Add file entry to 7zip archive.
    #
    # ==== Args
    # +filename+ :: File to be added to the 7zip archive. <tt>file</tt> must be a <b>relative path</b> if <tt>:as</tt> option is not specified.
    # +opt+ :: Optional hash parameter. <tt>:as</tt> key represents filename used in this archive.
    #
    # ==== Examples
    #   File.open("filename.7z", "wb") do |file|
    #     SevenZipRuby::SevenZipWriter.open(file) do |szw|
    #       # Add file entry 'test.txt' in 7zip archive.
    #       # This entry has the contents of the local file 'test.txt'.
    #       szw.add_file("test.txt")
    #
    #       # Add file entry 'desk/test.txt' in 7zip archive.
    #       # This entry has the contents of the local file 'C:/Users/test/Desktop/test2.txt'.
    #       szw.add_file("C:/Users/test/Desktop/test2.txt", as: "desk/test.txt")
    #     end
    #   end
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

    # Add file entry to 7zip archive.
    #
    # ==== Args
    # +data+ :: Data to be added to the 7zip archive.
    # +filename+ :: File name of the entry to be added to the 7zip archive. <tt>filename</tt> must be a <b>relative path</b>.
    # +opt+ :: Optional hash parameter. <tt>:ctime</tt>, <tt>:atime</tt> and <tt>:mtime</tt> keys can be specified as timestamp.
    #
    # ==== Examples
    #   File.open("filename.7z", "wb") do |file|
    #     SevenZipRuby::SevenZipWriter.open(file) do |szw|
    #       data = "1234567890"
    #
    #       # Add file entry 'data.bin' in 7zip archive.
    #       # This entry has the contents "1234567890".
    #       szw.add_data(data, "data.bin")
    #     end
    #   end
    def add_data(data, filename, opt={})
      path = Pathname(filename)
      raise ArgumentError.new("filename should be relative") if (path.absolute?)
      check_option(opt, [ :ctime, :atime, :mtime ])

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      add_item(UpdateInfo.buffer(name, data, opt))
      return self
    end

    # Add directory and files recursively to 7zip archive.
    #
    # ==== Args
    # +directory+ :: Directory to be added to the 7zip archive. <tt>directory</tt> must be a <b>relative path</b> if <tt>:as</tt> option is not specified.
    # +opt+ :: Optional hash parameter. <tt>:as</tt> key represents directory name used in this archive.
    #
    # ==== Examples
    #   File.open("filename.7z", "wb") do |file|
    #     SevenZipRuby::SevenZipWriter.open(file) do |szw|
    #       # Add "dir1" and entries under "dir" recursively.
    #       szw.add_directory("dir1")
    #
    #       # Add "C:/Users/test/Desktop/dir" and entries under it recursively.
    #       szw.add_directory("C:/Users/test/Desktop/dir", as: "test/dir")
    #     end
    #   end
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

      Pathname.glob(directory.join("**", "*").to_s, File::FNM_DOTMATCH) do |entry|
        basename = entry.basename.to_s
        next if (basename == "." || basename == "..")

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
    alias add_dir add_directory  # +add_dir+ is an alias of +add_directory+.

    # Add an entry of empty directory to 7zip archive.
    #
    # ==== Args
    # +directory_name+ :: Directory name to be added to 7z archive.
    # +opt+ :: Optional hash parameter. <tt>:ctime</tt>, <tt>:atime</tt> and <tt>:mtime</tt> keys can be specified as timestamp.
    #
    # ==== Examples
    #   File.open("filename.7z", "wb") do |file|
    #     SevenZipRuby::SevenZipWriter.open(file) do |szw|
    #       # Add an empty directory "dir1".
    #       szw.mkdir("dir1")
    #     end
    #   end
    def mkdir(directory_name, opt={})
      path = Pathname(directory_name)
      raise ArgumentError.new("directory_name should be relative") if (path.absolute?)
      check_option(opt, [ :ctime, :atime, :mtime ])

      name = path.cleanpath.to_s.encode(PATH_ENCODING)
      add_item(UpdateInfo.dir(name, opt))
      return self
    end


    def check_option(opt, keys)  # :nodoc:
      invalid_keys = opt.keys - keys
      raise ArgumentError.new("invalid option: " + invalid_keys.join(", ")) unless (invalid_keys.empty?)
    end
    private :check_option

    def compress_proc  # :nodoc:
      return Proc.new do |type, info|
        case(type)
        when :stream
          if (info.buffer?)
            #      type(filename/io), data
            next [ false, StringIO.new(info.data) ]
          elsif (info.file?)
            if (SevenZipWriter.use_native_input_file_stream)
              next [ true, info.data ]
            else
              next [ false, File.open(info.data, "rb") ]
            end
          else
            next nil
          end
        when :result
          info[:stream].close if (info[:stream])
        end
      end
    end
    private :compress_proc

    def add_sfx(stream, sfx)
      sfx = :default if sfx == true
      sfx_file = SFX_FILE_LIST[sfx]
      raise ArgumentError.new("invalid option: :sfx") unless sfx_file

      File.open(sfx_file, "rb") do |input|
        IO.copy_stream(input, stream)
      end
    end
    private :add_sfx

    COMPRESS_GUARD = Mutex.new  # :nodoc:
    def synchronize  # :nodoc:
      if (COMPRESS_GUARD)
        COMPRESS_GUARD.synchronize do
          yield
        end
      else
        yield
      end
    end
    private :synchronize
  end


  # +Writer+ is an alias of +SevenZipWriter+.
  Writer = SevenZipWriter
end
