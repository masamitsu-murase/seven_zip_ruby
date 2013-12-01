require("stringio")

module SevenZipRuby
  # SevenZipReader reads 7zip archive and extract it.
  class SevenZipReader
    class << self
      # Open 7zip archive.
      #
      # ==== Args
      # +stream+ :: Input stream of 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
      # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #  # Open archive
      #  File.open("filename.7z", "rb") do |file|
      #    SevenZipRuby::Reader.open(file) do |szr|
      #      # Read and extract archive.
      #    end
      #  end
      #
      #  # Open encrypted archive
      #  File.open("filename.7z", "rb") do |file|
      #    SevenZipRuby::Reader.open(file, password: "PasswordOfArchive") do |szr|
      #      # Read and extract archive.
      #    end
      #  end
      #
      #  # Open without block.
      #  File.open("filename.7z", "rb") do |file|
      #    szr = SevenZipRuby::Reader.open(file)
      #      # Read and extract archive.
      #    szr.close
      #  end
      def open(stream, param = {}, &block)
        szr = self.new
        szr.open(stream, param)
        if (block)
          block.call(szr)
          szr.close
        else
          szr
        end
      end

      # Open and extract 7zip archive.
      #
      # ==== Args
      # +stream+ :: Input stream of 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
      # +index+ :: Index of the entry to extract. Integer or Array of Integer can be specified.
      # +dir+ :: Directory to extract the archive to.
      # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::Reader.extract(file, 1, "path_to_dir")
      #   end
      #
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::Reader.extract(file, [1, 2, 4], "path_to_dir", password: "PasswordOfArchive")
      #   end
      def extract(stream, index, dir = ".", param = {})
        password = { password: param.delete(:password) }
        self.open(stream, password) do |szr|
          szr.extract(index, dir, param)
        end
      end

      # Open and extract 7zip archive.
      #
      # ==== Args
      # +stream+ :: Input stream of 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
      # +dir+ :: Directory to extract the archive to.
      # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   File.open("filename.7z", "rb") do |file|
      #     SevenZipRuby::Reader.extract_all(file, "path_to_dir")
      #   end
      def extract_all(stream, dir = ".", param = {})
        password = { password: param.delete(:password) }
        self.open(stream, password) do |szr|
          szr.extract_all(dir, param)
        end
      end

      # Open and verify 7zip archive.
      #
      # ==== Args
      # +stream+ :: Input stream of 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
      # +opt+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
      #
      # ==== Examples
      #   File.open("filename.7z", "rb") do |file|
      #     ret = SevenZipRuby::Reader.verify(file)
      #     # => true/false
      #   end
      def verify(stream, opt = {})
        szr = self.open(stream, opt)
        ret = szr.verify
        szr.close
        return ret
      end
    end

    # Open 7zip archive.
    #
    # ==== Args
    # +stream+ :: Input stream of 7zip archive. <tt>stream.seek</tt> and <tt>stream.read</tt> are needed.
    # +param+ :: Optional hash parameter. <tt>:password</tt> key represents password of this archive.
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     szr = SevenZipRuby::Reader.new
    #     szr.open(file)
    #     # ...
    #     szr.close
    #   end
    def open(stream, param = {})
      param[:password] = param[:password].to_s if (param[:password])
      stream.set_encoding(Encoding::ASCII_8BIT)
      open_impl(stream, param)
      return self
    end


    # :nodoc:
    def file_proc(base_dir)
      base_dir = base_dir.to_s
      return Proc.new do |type, arg|
        case(type)
        when :stream
          ret = nil
          if (arg.anti?)
            arg.path.rmtree if (arg.path.exist?)
          elsif (arg.file?)
            path = arg.path.expand_path(base_dir)
            path.parent.mkpath
            ret = File.open(path, "wb")
          else
            path = arg.path.expand_path(base_dir)
            path.mkpath
            set_file_attribute(path.to_s, arg.attrib) if (arg.attrib)
            path.utime(arg.atime || path.atime, arg.mtime || path.mtime)
          end
          next ret

        when :result
          arg[:stream].close
          unless (arg[:info].anti?)
            path = arg[:info].path.expand_path(base_dir)
            set_file_attribute(path.to_s, arg[:info].attrib) if (arg[:info].attrib)
            path.utime(arg[:info].atime || path.atime, arg[:info].mtime || path.mtime)
          end
        end
      end
    end
    private :file_proc

    # :nodoc:
    def data_proc(output, idx_prj)
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
          if (arg[:info].has_data?)
            output[idx_prj[arg[:info].index]] = arg[:stream].string
          end

        end
      end
    end
    private :data_proc


    # Verify 7zip archive.
    #
    # ==== Args
    # none
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::Reader.open(file) do |szr|
    #       ret = szr.verify
    #       # => true/false
    #     end
    #   end
    def test
      begin
        return test_all_impl(nil)
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
    #     SevenZipRuby::Reader.open(file) do |szr|
    #       ret = szr.verify_detail
    #       # => [ true, :DataError, :DataError, ... ]
    #     end
    #   end
    def verify_detail
      begin
        return test_all_impl(true)
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
    #     SevenZipRuby::Reader.open(file) do |szr|
    #       szr.extract([ 1, 2, 4 ], "path_to_dir")
    #     end
    #   end
    def extract(index, dir = ".")
      path = File.expand_path(dir)
      case(index)
      when Symbol
        raise SevenZipError.new("Argument error") unless (index == :all)
        return extract_all(path)
      when Array
        index_list = index.map(&:to_i).sort.uniq
        extract_files_impl(index_list, file_proc(path))
      else
        extract_impl(index.to_i, file_proc(path))
      end
    end

    # Extract all entries of 7zip archive to local directory.
    #
    # ==== Args
    # +dir+ :: Directory to extract the archive to.
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::Reader.open(file) do |szr|
    #       szr.extract_all("path_to_dir")
    #     end
    #   end
    def extract_all(dir = ".")
      extract_all_impl(file_proc(File.expand_path(dir)))
    end

    # Extract entires of 7zip archive to local directory based on the block return value.
    #
    # ==== Args
    # +dir+ :: Directory to extract the archive to.
    #
    # ==== Examples
    #   # Extract files whose size is less than 1024.
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::Reader.open(file) do |szr|
    #       szr.extract_if("path_to_dir") do |entry|
    #         next entry.size < 1024
    #       end
    #     end
    #   end
    def extract_if(dir = ".", &block)
      extract(entries.select(&block).map(&:index), dir)
    end

    # Extract some entries of 7zip archive and return the extracted data.
    #
    # ==== Args
    # +index+ :: Index of the entry to extract. :all, Integer or Array of Integer can be specified.
    #
    # ==== Examples
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::Reader.open(file) do |szr|
    #       small_entries = szr.entries.select{ |i| i.size < 1024 }
    #
    #       data_list = szr.extract_data(small_entries)
    #       # => [ "file contents1", "file contents2", ... ]
    #     end
    #   end
    #
    #   File.open("filename.7z", "rb") do |file|
    #     SevenZipRuby::Reader.open(file) do |szr|
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
        extract_all_impl(data_proc(ret, idx_prj))
        return ret

      when Array
        index_list = index.map(&:to_i)
        idx_prj = Hash[*(index_list.each_with_index.map{ |idx, i| [ idx, i ] }.flatten)]

        ret = []
        extract_files_impl(index_list, data_proc(ret, idx_prj))
        return ret

      else
        index = index.to_i
        item = entry(index)
        return nil unless (item.has_data?)

        idx_prj = Object.new
        def idx_prj.[](index)
          return 0
        end

        ret = []
        extract_impl(index, data_proc(ret, idx_prj))
        return ret[0]

      end
    end
  end


  Reader = SevenZipReader
end
