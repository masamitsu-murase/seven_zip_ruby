require("stringio")

module SevenZipRuby
  class SevenZipReader
    class << self
      def open(*args, &block)
        szr = self.new
        szr.open(*args)
        if (block)
          begin
            block.call(szr)
          ensure
            szr.close
          end
        else
          szr
        end
      end
    end

    def open(stream, param = {})
      param[:password] = param[:password].to_s if (param[:password])
      open_impl(stream, param)
      return self
    end


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


    def test
      begin
        return test_all_impl(nil)
      rescue
        return false
      end
    end
    alias verify test

    def verify_detail
      begin
        return test_all_impl(true)
      rescue
        return nil
      end
    end

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

    def extract_all(dir = ".")
      extract_all_impl(file_proc(File.expand_path(dir)))
    end

    def extract_if(dir = ".", &block)
      extract(entries.select(&block).map(&:index), dir)
    end

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
end
