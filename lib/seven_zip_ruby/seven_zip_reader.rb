require("stringio")
require("thread")

module SevenZipRuby

  # SevenZipReader reads 7zip archive and extract it.
  #
  # == Examples
  # === Get archive information
  #   # Archive property
  #   File.open("filename.7z", "rb") do |file|
  #     SevenZipRuby::Reader.open(file) do |szr|
  #       info = szr.archive_property  # Return ArchiveInfo instance.
  #     end
  #   end
  #
  #   # Entry information
  #   File.open("filename.7z", "rb") do |file|
  #     SevenZipRuby::Reader.open(file) do |szr|
  #       entries = szr.entries
  #     end
  #   end
  #
  # === Extract 7zip archive.
  #   # Extract archive
  #   File.open("filename.7z", "rb") do |file|
  #     SevenZipRuby::Reader.open(file) do |szr|
  #       szr.extract(:all, "path_to_dir")
  #     end
  #   end
  #
  #   # Extract archive 2
  #   SevenZipRuby::Reader.open_file("filename.7z") do |szr|
  #     szr.extract(:all, "path_to_dir")
  #   end
  #
  #   # Extract encrypted archive
  #   File.open("filename.7z", "rb") do |file|
  #     SevenZipRuby::Reader.open(file, password: "Password String") do |szr|
  #       szr.extract(:all, "path_to_dir")
  #     end
  #   end
  #
  #   # Extract only small files
  #   File.open("filename.7z", "rb") do |file|
  #     SevenZipRuby::Reader.open(file) do |szr|
  #       small_files = szr.entries.select{ |i| i.file? && i.size < 1024 }
  #       szr.extract(small_files, "path_to_dir")
  #     end
  #   end
  #
  #   # Extract archive on memory
  #   archive_data = "....."
  #   stream = StringIO.new(archive_data)
  #   SevenZipRuby::Reader.open(stream) do |szr|
  #     entry_data = szr.extract_data(:all)
  #     # => [ "data", ... ]
  #   end
  #
  # === Verify archive
  #   File.open("filename.7z", "rb") do |file|
  #     SevenZipRuby::Reader.verify(file)
  #     # => true/false
  #   end
  class SevenZipReader
    class << self
      # Open 7zip archive to read.
      #
      # ==== Args
      # +stream+ :: Input stream to read 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
      # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   # Open archive
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::SevenZipReader.open(file) do |szr|
      #       # Read and extract archive.
      #     end
      #   end
      #
      #   # Open encrypted archive
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::SevenZipReader.open(file, password: "PasswordOfArchive") do |szr|
      #       # Read and extract archive.
      #     end
      #   end
      #
      #   # Open without block.
      #   File.open("filename.7z", "rb") do |file|
      #     szr = SevenZipRuby::SevenZipReader.open(file)
      #     # Read and extract archive.
      #     szr.close
      #   end
      #
      #   # Open archive on memory.
      #   archive_data = "....."
      #   stream = StringIO.new(archive_data)
      #   SevenZipRuby::Reader.open(stream) do |szr|
      #     szr.extract(:all, "path_to_dir")
      #   end
      def open(stream, param = {}, &block)  # :yield: szr
        szr = self.new
        szr.open(stream, param)
        if (block)
          begin
            block.call(szr)
            szr.close
          ensure
            szr.close_file
          end
        else
          szr
        end
      end


      # Open 7zip archive to read.
      #
      # ==== Args
      # +filename+ :: Filename of 7zip archive.
      # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   # Open archive
      #   SevenZipRuby::SevenZipReader.open_file("filename.7z") do |szr|
      #     # Read and extract archive.
      #   end
      #
      #   # Open encrypted archive
      #   SevenZipRuby::SevenZipReader.open_file("filename.7z", password: "PasswordOfArchive") do |szr|
      #     # Read and extract archive.
      #   end
      #
      #   # Open without block.
      #   szr = SevenZipRuby::SevenZipReader.open_file("filename.7z")
      #   # Read and extract archive.
      #   szr.close
      def open_file(filename, param = {}, &block)  # :yield: szr
        szr = self.new
        szr.open_file(filename, param)
        if (block)
          begin
            block.call(szr)
            szr.close
          ensure
            szr.close_file
          end
        else
          szr
        end
      end


      # Open and extract 7zip archive.
      #
      # ==== Args
      # +stream+ :: Input stream to read 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed, such as <tt>File</tt> and <tt>StringIO</tt>.
      # +index+ :: Index of the entry to extract. Integer or Array of Integer can be specified.
      # +dir+ :: Directory to extract the archive to.
      # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::SevenZipReader.extract(file, 1, "path_to_dir")
      #   end
      #
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::SevenZipReader.extract(file, [1, 2, 4], "path_to_dir", password: "PasswordOfArchive")
      #   end
      #
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::SevenZipReader.extract(file, :all, "path_to_dir")
      #   end
      def extract(stream, index, dir = ".", param = {})
        password = { password: param.delete(:password) }
        self.open(stream, password) do |szr|
          szr.extract(index, dir)
        end
      end

      # Open and extract 7zip archive.
      #
      # ==== Args
      # +stream+ :: Input stream to read 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
      # +dir+ :: Directory to extract the archive to.
      # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::SevenZipReader.extract_all(file, "path_to_dir")
      #   end
      def extract_all(stream, dir = ".", param = {})
        password = { password: param.delete(:password) }
        self.open(stream, password) do |szr|
          szr.extract_all(dir)
        end
      end

      # Open and verify 7zip archive.
      #
      # ==== Args
      # +stream+ :: Input stream to read 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
      # +opt+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   File.open("filename.7z", "rb") do |file|
      #     ret = SevenZipRuby::SevenZipReader.verify(file)
      #     # => true/false
      #   end
      def verify(stream, opt = {})
        ret = false
        begin
          self.open(stream, opt) do |szr|
            ret = szr.verify
          end
        rescue
          ret = false
        end
        return ret
      end
    end

    undef initialize_copy, clone, dup

    # Open 7zip archive.
    #
    # ==== Args
    # +stream+ :: Input stream to read 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
    # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     szr = SevenZipRuby::SevenZipReader.new
    #     szr.open(file)
    #     # ...
    #     szr.close
    #   end
    def open(stream, param = {})
      param = param.clone
      param[:password] = param[:password].to_s if (param[:password])
      stream.set_encoding(Encoding::ASCII_8BIT)
      open_impl(stream, param)
      return self
    end

    # Open 7zip archive file.
    #
    # ==== Args
    # +filename+ :: Filename of 7zip archive.
    # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
    #
    # ==== Examples
    #   szr = SevenZipRuby::SevenZipReader.new
    #   szr.open_file("filename.7z")
    #   # ...
    #   szr.close
    def open_file(filename, param = {})
      @stream = File.open(filename, "rb")
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

    # Verify 7zip archive.
    #
    # ==== Args
    # none
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       ret = szr.verify
    #       # => true/false
    #     end
    #   end
    def test
      begin
        synchronize do
          return test_all_impl(nil)
        end
      rescue
        return false
      end
    end
    alias verify test

    # Verify 7zip archive and return the result of each entry.
    #
    # ==== Args
    # none
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       ret = szr.verify_detail
    #       # => [ true, :DataError, :DataError, ... ]
    #     end
    #   end
    def verify_detail
      begin
        synchronize do
          return test_all_impl(true)
        end
      rescue
        return nil
      end
    end

    # Extract some entries of 7zip archive to local directory.
    #
    # ==== Args
    # +index+ :: Index of the entry to extract. Integer or Array of Integer can be specified.
    # +dir+ :: Directory to extract the archive to.
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       szr.extract([ 1, 2, 4 ], "path_to_dir")
    #     end
    #   end
    #
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       szr.extract(:all, "path_to_dir")
    #     end
    #   end
    def extract(index, dir = ".")
      path = File.expand_path(dir)
      case(index)
      when Symbol
        raise SevenZipError.new("Argument error") unless (index == :all)
        return extract_all(path)
      when Enumerable
        index_list = index.map(&:to_i).sort.uniq
        synchronize do
          extract_files_impl(index_list, file_proc(path))
        end
      when nil
        raise ArgumentError.new("Invalid parameter index")
      else
        synchronize do
          extract_impl(index.to_i, file_proc(path))
        end
      end
    end

    # Extract all entries of 7zip archive to local directory.
    #
    # ==== Args
    # +dir+ :: Directory to extract the archive to.
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       szr.extract_all("path_to_dir")
    #     end
    #   end
    def extract_all(dir = ".")
      synchronize do
        extract_all_impl(file_proc(File.expand_path(dir)))
      end
    end

    # Extract entires of 7zip archive to local directory based on the block return value.
    #
    # ==== Args
    # +dir+ :: Directory to extract the archive to.
    #
    # ==== Examples
    #   # Extract files whose size is less than 1024.
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       szr.extract_if("path_to_dir") do |entry|
    #         next entry.size < 1024
    #       end
    #     end
    #   end
    def extract_if(dir = ".", &block)  # :yield: entry_info
      extract(entries.select(&block).map(&:index), dir)
    end

    # Extract some entries of 7zip archive and return the extracted data.
    #
    # ==== Args
    # +index+ :: Index of the entry to extract. :all, Integer or Array of Integer can be specified.
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       small_entries = szr.entries.select{ |i| i.size < 1024 }
    #
    #       data_list = szr.extract_data(small_entries)
    #       # => [ "file contents1", "file contents2", ... ]
    #     end
    #   end
    #
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::SevenZipReader.open(file) do |szr|
    #       largest_entry = szr.entries.max_by{ |i| i.file? ? i.size : 0 }
    #
    #       data_list = szr.extract_data(largest_entry)
    #       # => "file contents..."
    #     end
    #   end
    def extract_data(index)
      case(index)
      when :all
        idx_prj = Object.new
        def idx_prj.[](index)
          return index
        end

        ret = []
        synchronize do
          extract_all_impl(data_proc(ret, idx_prj))
        end
        return ret

      when Enumerable
        index_list = index.map(&:to_i)
        idx_prj = Hash[*(index_list.each_with_index.map{ |idx, i| [ idx, i ] }.flatten)]

        ret = []
        synchronize do
          extract_files_impl(index_list, data_proc(ret, idx_prj))
        end
        return ret

      when nil
        raise ArgumentError.new("Invalid parameter index")

      else
        index = index.to_i
        item = entry(index)
        return nil unless (item.has_data?)

        idx_prj = Object.new
        def idx_prj.[](index)
          return 0
        end

        ret = []
        synchronize do
          extract_impl(index, data_proc(ret, idx_prj))
        end
        return ret[0]

      end
    end


    def file_proc(base_dir)  # :nodoc:
      base_dir = base_dir.to_s
      base_dir = File.expand_path(base_dir)
      return Proc.new do |type, arg|
        case(type)
        when :stream
          ret = nil
          arg_path = Pathname(arg.path)
          rp = arg_path.cleanpath
          if "..#{File::SEPARATOR}" == rp.to_s[0..2]
            raise InvalidArchive.new("#{arg.path} is Dangerous Path.")
          end
          if (arg.anti?)
            pwd = Dir.pwd
            Dir.chdir(base_dir)
            rp = File.join(".", arg_path.to_s)
            begin
              if (File.exist?(rp))
                require 'fileutils'
                FileUtils.remove_entry_secure(rp)
              end
            ensure
              Dir.chdir(pwd) rescue nil
            end
          elsif (arg.file?)
            path = arg_path.expand_path(base_dir)
            path.parent.mkpath
            ret = File.open(path, "wb")
          else
            path = arg_path.expand_path(base_dir)
            path.mkpath
            set_file_attribute(path.to_s, arg.attrib) if (arg.attrib)
            path.utime(arg.atime || path.atime, arg.mtime || path.mtime) rescue nil
          end
          next ret

        when :result
          arg[:stream].close
          raise InvalidArchive.new("Corrupted archive or invalid password") unless (arg[:success])

          unless (arg[:info].anti?)
            path = Pathname(arg[:info].path).expand_path(base_dir)
            set_file_attribute(path.to_s, arg[:info].attrib) if (arg[:info].attrib)
            path.utime(arg[:info].atime || path.atime, arg[:info].mtime || path.mtime) rescue nil
          end
        end
      end
    end
    private :file_proc

    def data_proc(output, idx_prj)  # :nodoc:
      return Proc.new do |type, arg|
        case(type)
        when :stream
          ret = (arg.has_data? ? StringIO.new("".b) : nil)
          unless (arg.has_data?)
            output[idx_prj[arg.index]] = nil
          end
          next ret

        when :result
          arg[:stream].close
          raise InvalidArchive.new("Corrupted archive or invalid password") unless (arg[:success])

          if (arg[:info].has_data?)
            output[idx_prj[arg[:info].index]] = arg[:stream].string
          end

        end
      end
    end
    private :data_proc

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


  # +Reader+ is an alias of +SevenZipReader+.
  Reader = SevenZipReader
end
