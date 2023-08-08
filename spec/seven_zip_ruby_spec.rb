require("seven_zip_ruby")
require_relative("seven_zip_ruby_spec_helper")

describe SevenZipRuby do
  before(:all) do
    SevenZipRubySpecHelper.prepare_all
    # GC.stress = true
  end

  after(:all) do
    # GC.stress = false
    SevenZipRubySpecHelper.cleanup_all
  end

  before(:each) do
    @use_native_input_file_stream = SevenZipRuby::SevenZipWriter.use_native_input_file_stream
    SevenZipRubySpecHelper.prepare_each
  end

  after(:each) do
    SevenZipRubySpecHelper.cleanup_each
    SevenZipRuby::SevenZipWriter.use_native_input_file_stream = @use_native_input_file_stream
  end


  describe SevenZipRuby::SevenZipReader do

    example "get entry information in the archive" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        szr = SevenZipRuby::SevenZipReader.new
        szr.open(file)
        entries = szr.entries

        expect(entries.size).to be SevenZipRubySpecHelper::SAMPLE_DATA.size

        SevenZipRubySpecHelper::SAMPLE_DATA.each do |sample|
          entry = entries.select{ |i| i.path == Pathname(sample[:name]).cleanpath.to_s }
          expect(entry.size).to be 1

          entry = entry[0]
          expect(entry.directory?).to be sample[:directory]
        end

        szr.close
      end
    end

    example "get archive information" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        SevenZipRuby::SevenZipReader.open(file) do |szr|
          info = szr.archive_property

          expect(info.num_blocks).to be_a Integer
          expect(info.header_size).to be < file.size
          expect(info.method).to eq "LZMA:16"
          expect(info.phy_size).to be file.size
          expect(info.solid?).to be true
        end
      end
    end

    example "extract data directly from archive" do
      SevenZipRuby::SevenZipReader.open_file(SevenZipRubySpecHelper::SEVEN_ZIP_FILE) do |szr|
        entries = szr.entries

        SevenZipRubySpecHelper::SAMPLE_DATA.each do |sample|
          entry = entries.find{ |i| i.path == Pathname(sample[:name]).cleanpath.to_s }
          expect(szr.extract_data(entry.index)).to eq sample[:data]
        end
      end
    end

    example "extract selected data from archive" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        SevenZipRuby::SevenZipReader.open(file) do |szr|
          entries = szr.entries.select{ |i| i.file? }
          expect(szr.extract_data(entries).all?).to eq true
        end
      end
    end

    example "singleton method: extract" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        SevenZipRuby::SevenZipReader.extract(file, :all, SevenZipRubySpecHelper::EXTRACT_DIR)
      end
    end

    example "singleton method: extract_all" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        SevenZipRuby::SevenZipReader.extract_all(file, SevenZipRubySpecHelper::EXTRACT_DIR)
      end
    end

    example "singleton method: verify" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        SevenZipRuby::SevenZipReader.verify(file)
      end
    end

    example "extract archive" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        SevenZipRuby::SevenZipReader.open(file) do |szr|
          szr.extract_all(SevenZipRubySpecHelper::EXTRACT_DIR)
        end
      end

      Dir.chdir(SevenZipRubySpecHelper::EXTRACT_DIR) do
        SevenZipRubySpecHelper::SAMPLE_DATA.each do |info|
          path = Pathname(info[:name])
          expected_path = Pathname(SevenZipRubySpecHelper::SAMPLE_FILE_DIR) + info[:name]
          # Do not check mtime because seven_zip.7z is not compressed dynamically.
          # expect(path.mtime.to_i).to eq expected_path.mtime.to_i
          expect(path.file?).to eq expected_path.file?
          (expect(File.open(path, "rb", &:read)).to eq info[:data]) if (path.file?)
        end
      end
    end

    example "run in another thread" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        szr = nil
        sample = nil
        entry = nil
        th = Thread.new do
          szr = SevenZipRuby::SevenZipReader.open(file)
          sample = SevenZipRubySpecHelper::SAMPLE_DATA.sample
          entry = szr.entries.find{ |i| i.path == Pathname(sample[:name]).cleanpath.to_s }
        end
        th.join

        expect(szr.extract_data(entry.index)).to eq sample[:data]
      end
    end

    example "test archive" do
      data = File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb", &:read)
      SevenZipRuby::SevenZipReader.open(StringIO.new(data)) do |szr|
        expect(szr.test).to eq true
      end

      expect(SevenZipRuby::SevenZipReader.verify(StringIO.new(data))).to eq true

      data_org = data[-1]
      data[-1] = 0x01.chr  # This highly dependes on the current test binary.
      expect(SevenZipRuby::SevenZipReader.verify(StringIO.new(data))).to eq false
      data[-1] = data_org

      data[0x27] = 0xEB.chr  # This highly dependes on the current test binary.
      expected = [ :CrcError, :CrcError, :CrcError, :CrcError, :DataError, :DataError, :DataError, true, true, true, true, true ]
      SevenZipRuby::SevenZipReader.open(StringIO.new(data)) do |szr|
        expect(szr.test).to eq false
        expect(szr.verify_detail).to eq expected
      end


      data = File.open(SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD_FILE, "rb", &:read)
      SevenZipRuby::SevenZipReader.open(StringIO.new(data), { password: SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD }) do |szr|
        expect(szr.verify).to eq true
      end

      SevenZipRuby::SevenZipReader.open(StringIO.new(data), { password: "wrong password" }) do |szr|
        expect(szr.verify).to eq false
      end

      expected = [ :DataError, :DataError, :DataError, :DataError, :DataError, :DataError, :DataError, true, true, true, true, true ]
      SevenZipRuby::SevenZipReader.open(StringIO.new(data), { password: "wrong password" }) do |szr|
        expect(szr.verify_detail).to eq expected
      end
    end

    example "run in multi threads" do
      s = StringIO.new
      SevenZipRuby::SevenZipWriter.open(s) do |szw|
        szw.add_data(SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA, "data.bin")
      end
      data = s.string

      th_list = []
      100.times do
        th = Thread.new do
          stream = StringIO.new(data)
          SevenZipRuby::SevenZipReader.open(stream) do |szr|
            szr.extract_data(0)
          end
        end
        th_list.push(th)
      end
      th_list.each(&:join)
    end


    describe "error handling" do

      example "throw in method" do
        [ :read, :seek ].each do |method|
          catch do |tag|
            File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
              file.define_singleton_method(method) do |*args|
                throw tag
              end
              expect{ SevenZipRuby::SevenZipReader.open(file) }.to raise_error(ArgumentError)
            end
          end
        end
      end

      example "invalid index" do
        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
          SevenZipRuby::SevenZipReader.open(file) do |szr|
            expect{ szr.extract_data(nil) }.to raise_error(ArgumentError)
          end
        end
      end

      example "invalid index for entry" do
        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
          SevenZipRuby::SevenZipReader.open(file) do |szr|
            expect{ szr.entry("a") }.to raise_error(TypeError)
          end
        end
      end

      example "invalid password" do
#        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD_FILE, "rb") do |file|
#          expect{ SevenZipRuby::Reader.open(file){ |szr| szr.extract_data(1) } }.to raise_error(StandardError)
#        end

        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD_FILE, "rb") do |file|
          SevenZipRuby::Reader.open(file) do |szr|
            expect(szr.extract_data(1)).to be_nil
          end
        end

        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD_FILE, "rb") do |file|
          SevenZipRuby::Reader.open(file, password: "a") do |szr|
            expect(szr.extract_data(1)).to be_nil
          end
        end

        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD_FILE, "rb") do |file|
          SevenZipRuby::Reader.open(file, password: :InvalidType) do |szr|
            expect(szr.extract_data(1)).to be_nil
          end
        end

      end

      example "raise error in open" do
        error = StandardError.new

        [ :read, :seek ].each do |method|
          file = File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb")
          file.define_singleton_method(method) do |*args|
            raise error
          end
          expect{ SevenZipRuby::SevenZipReader.open(file) }.to raise_error(error)
          file.close
        end
      end

      example "raise error after open" do
        error = StandardError.new

        [ :read, :seek ].each do |method|
          file = File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb")

          szr = nil
          expect{ szr = SevenZipRuby::SevenZipReader.open(file) }.not_to raise_error

          file.define_singleton_method(method) do |*args|
            raise error
          end
          expect{ szr.extract_data(1) }.to raise_error(error)

          file.close
        end
      end

      example "try to extract/entries before open" do
        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
          szr = SevenZipRuby::SevenZipReader.new
          expect{ szr.extract_data(1) }.to raise_error(SevenZipRuby::InvalidOperation)
          expect{ szr.entry(1) }.to raise_error(SevenZipRuby::InvalidOperation)
        end
      end

      example "try to extract/entries after close" do
        File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
          szr = SevenZipRuby::SevenZipReader.open(file)
          szr.close

          expect{ szr.extract_data(1) }.to raise_error(SevenZipRuby::InvalidOperation)
          expect{ szr.entry(1) }.to raise_error(SevenZipRuby::InvalidOperation)
        end
      end

      example "kill thread" do
        th = Thread.start do
          File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
            class << file
              alias orig_read read

              def read(*args)
                sleep 2
                return orig_read(*args)
              end
            end

            SevenZipRuby::SevenZipReader.open(file)
          end
        end

        sleep 1
        expect{ th.kill }.not_to raise_error  # Thread can be killed.
      end

      example "clone and dup cannot be called." do
        expect{ SevenZipRuby::SevenZipReader.new.clone }.to raise_error(NoMethodError)
        expect{ SevenZipRuby::SevenZipReader.new.dup }.to raise_error(NoMethodError)
      end

    end

  end


  describe SevenZipRuby::SevenZipWriter do

    example "compress without block" do
      output = StringIO.new("")
      szw = SevenZipRuby::SevenZipWriter.new
      szw.open(output)
      szw.add_data("This is hoge.txt content.", "hoge.txt")
      szw.add_data("This is hoge2.txt content.", "hoge2.txt")
      szw.mkdir("hoge/hoge/hoge")
      szw.compress
      szw.close

      output.rewind
      expect(SevenZipRuby::SevenZipReader.verify(output)).to eq true
    end

    example "compress" do
      output = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output) do |szw|
        szw.add_data("This is hoge.txt content.", "hoge.txt")
        szw.add_data("This is hoge2.txt content.", "hoge2.txt")
        szw.mkdir("hoge/hoge/hoge")
        szw.compress
      end

      output.rewind
      expect(SevenZipRuby::SevenZipReader.verify(output)).to eq true
    end

    example "open_file" do
      FileUtils.mkpath(SevenZipRubySpecHelper::EXTRACT_DIR)
      Dir.chdir(SevenZipRubySpecHelper::EXTRACT_DIR) do
        filename = "hoge.7z"

        SevenZipRuby::SevenZipWriter.open_file(filename) do |szw|
          szw.add_data("This is a sample.", "hoge.txt")
        end

        File.open(filename, "rb") do |f|
          expect(SevenZipRuby::SevenZipReader.verify(f)).to eq true
        end
      end
    end

    example "compress local file" do
      Dir.chdir(SevenZipRubySpecHelper::SAMPLE_FILE_DIR) do
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          data = SevenZipRubySpecHelper::SAMPLE_DATA[0]
          szw.add_file(data[:name])
        end

        output.rewind
        SevenZipRuby::SevenZipReader.open(output) do |szr|
          data = SevenZipRubySpecHelper::SAMPLE_DATA[0]
          expect(szr.entries[0].path.to_s).to eq data[:name]
          expect(szr.extract_data(0)).to eq data[:data]
        end
      end
    end

    example "set password" do
      sample_data = "Sample Data"
      sample_password = "sample password"

      output = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output, { password: sample_password }) do |szw|
        szw.add_data(sample_data, "hoge.txt")
      end

      output.rewind
      SevenZipRuby::SevenZipReader.open(output, { password: sample_password }) do |szr|
        expect(szr.extract_data(0)).to eq sample_data
      end

      output.rewind
      SevenZipRuby::SevenZipReader.open(output, { password: "invalid password"}) do |szr|
        expect(szr.extract_data(0)).to be_nil
      end

      output = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output, { password: sample_password.to_sym }) do |szw|
        szw.add_data(sample_data, "hoge.txt")
      end

      output.rewind
      SevenZipRuby::SevenZipReader.open(output, { password: sample_password }) do |szr|
        expect(szr.extract_data(0)).to eq sample_data
      end
    end

    example "create a sfx archive" do
      time = Time.now

      output = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output) do |szw|
        szw.add_data("hogehoge", "hoge.txt", ctime: time, atime: time, mtime: time)
      end

      output1 = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output1, sfx: true) do |szw|
        szw.add_data("hogehoge", "hoge.txt", ctime: time, atime: time, mtime: time)
      end

      output2 = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output2, sfx: :gui) do |szw|
        szw.add_data("hogehoge", "hoge.txt", ctime: time, atime: time, mtime: time)
      end

      output3 = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output3, sfx: :console) do |szw|
        szw.add_data("hogehoge", "hoge.txt", ctime: time, atime: time, mtime: time)
      end

      gui = File.open(SevenZipRuby::SevenZipWriter::SFX_FILE_LIST[:gui], "rb", &:read)
      console = File.open(SevenZipRuby::SevenZipWriter::SFX_FILE_LIST[:console], "rb", &:read)

      expect(output1.string).to eq gui + output.string
      expect(output2.string).to eq gui + output.string
      expect(output3.string).to eq console + output.string
    end

    [ true, false ].each do |use_native_input_file_stream|
      example "add_directory: use_native_input_file_stream=#{use_native_input_file_stream}" do
        SevenZipRuby::SevenZipWriter.use_native_input_file_stream = use_native_input_file_stream

        Dir.chdir(SevenZipRubySpecHelper::SAMPLE_FILE_DIR) do
          output = StringIO.new("")
          SevenZipRuby::SevenZipWriter.open(output) do |szw|
            Pathname.glob("*", File::FNM_DOTMATCH) do |path|
              basename = path.basename.to_s
              next if (basename == "." || basename == "..")

              if (path.file?)
                szw.add_file(path)
              else
                szw.add_directory(path)
              end
            end
          end

          output.rewind
          SevenZipRuby::SevenZipReader.open(output) do |szr|
            entries = szr.entries
            expect(entries.size).to eq SevenZipRubySpecHelper::SAMPLE_DATA.size

            entries.each do |entry|
              entry_in_sample = SevenZipRubySpecHelper::SAMPLE_DATA.find{ |i| i[:name] == entry.path.to_s }
              local_entry = Pathname(File.join(SevenZipRubySpecHelper::SAMPLE_FILE_DIR, entry_in_sample[:name]))
              if (entry_in_sample[:directory])
                expect(entry.directory?).to eq true
              else
                expect(szr.extract_data(entry)).to eq File.open(entry_in_sample[:name], "rb", &:read)
              end
              expect(entry.mtime.to_i).to eq local_entry.mtime.to_i
            end
          end
        end
      end

      example "add_directory singleton version: use_native_input_file_stream=#{use_native_input_file_stream}" do
        SevenZipRuby::SevenZipWriter.use_native_input_file_stream = use_native_input_file_stream

        dir = File.join(SevenZipRubySpecHelper::SAMPLE_FILE_DIR, "..")
        dirname = File.basename(SevenZipRubySpecHelper::SAMPLE_FILE_DIR)
        Dir.chdir(dir) do
          output = StringIO.new("")
          SevenZipRuby::SevenZipWriter.add_directory(output, dirname)

          output2 = StringIO.new("")
          SevenZipRuby::SevenZipWriter.open(output2) do |szr|
            szr.add_directory(dirname)
          end

          expect(output.string).to eq output2.string
        end
      end
    end  # use_native_input_file_stream

    example "use as option" do
      output = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output) do |szw|
        szw.add_directory(SevenZipRubySpecHelper::SAMPLE_FILE_DIR, as: "test/dir")
      end

      output.rewind
      SevenZipRuby::SevenZipReader.open(output) do |szr|
        base_dir = Pathname(SevenZipRubySpecHelper::SAMPLE_FILE_DIR)
        entries = szr.entries
        files = Pathname.glob(base_dir.to_s + "/**/*", File::FNM_DOTMATCH) + [ base_dir ]
        files = files.select{ |i| i.basename.to_s != "." && i.basename.to_s != ".." }

        expect(entries.size).to eq files.size

        expect(entries.all?{ |i| i.path.start_with?("test/dir") }).to eq true

        entries.each do |entry|
          file = files.find do |i|
            i.relative_path_from(base_dir) == Pathname(entry.path).relative_path_from(Pathname("test/dir"))
          end
          expect(file.directory?).to eq entry.directory?
        end
      end
    end

    example "use various methods" do
      [ "COPY", "DEFLATE", "LZMA", "LZMA2", "BZIP2", "PPMd" ].each do |type|
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          szw.method = type
          szw.add_data(SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA, "hoge.txt")
        end

        SevenZipRuby::SevenZipReader.open(StringIO.new(output.string)) do |szr|
          expect(szr.extract_data(0)).to eq SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
        end
      end
    end

    example "set compression level" do
      size = [ 0, 1, 3, 5, 7, 9 ].map do |level|
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          szw.level = level
          data = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
          time = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA_TIMESTAMP
          szw.add_data(data, "hoge1.txt", mtime: time)
          szw.add_data(data + data.slice(1 .. -1), "hoge2.txt", mtime: time)
          szw.add_data(data + data.reverse + data.slice(1 .. -1), "hoge3.txt", mtime: time)
        end
        next output.string.size
      end
      size.each_cons(2) do |large, small|
# test data is not that random :)
# higher compression level may have _small_ negative effect
        expect(large - small >= -8).to eq true
      end
    end

    example "set solid" do
      size = [ false, true ].map do |solid|
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          szw.solid = solid
          data = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
          szw.add_data(data, "hoge1.txt")
          szw.add_data(data + data.slice(1 .. -1), "hoge2.txt")
        end
        next output.string.size
      end
      expect(size.sort.reverse).to eq size
    end

    example "set header_compression" do
      size = [ false, true ].map do |header_compression|
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          szw.header_compression = header_compression
          data = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
          10.times do |i|
            szw.add_data(data, "hoge#{i}.txt")
          end
        end
        next output.string.size
      end
      expect(size.sort.reverse).to eq size
    end

    example "run in multi threads" do
      th_list = []
      100.times do
        th = Thread.new do
          stream = StringIO.new
          SevenZipRuby::SevenZipWriter.open(stream) do |szw|
            data = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
            szw.add_data(data, "hoge.dat")
          end
        end
        th_list.push(th)
      end
      th_list.each(&:join)
    end

    if (SevenZipRubySpecHelper.processor_count && SevenZipRubySpecHelper.processor_count > 1)
      example "set multi_thread" do
        time = [ false, true ].map do |multi_thread|
          output = StringIO.new("")
          start = nil
          SevenZipRuby::SevenZipWriter.open(output) do |szw|
            szw.method = "BZIP2"  # BZIP2 uses multi threads.
            szw.multi_thread = multi_thread
            data = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
            szw.add_data(data * 10, "hoge.txt")
            start = Time.now
          end
          next Time.now - start
        end
        expect(time.sort.reverse).to eq time
      end
    end


    describe "error handling" do

      example "raise error in update" do
        error = StandardError.new

        [ :write, :seek ].each do |method|
          output = StringIO.new("")
          output.define_singleton_method(method) do |*args|
            raise error
          end
          expect{ SevenZipRuby::SevenZipWriter.open(output).compress }.to raise_error(error)
        end
      end

      example "invalid method" do
        expect{ SevenZipRuby::SevenZipWriter.open(StringIO.new("")).method = "Unknown" }.to raise_error(ArgumentError)
      end

      example "invalid level" do
        expect{ SevenZipRuby::SevenZipWriter.open(StringIO.new("")).level = 2 }.to raise_error(ArgumentError)
      end

      example "add_data/mkdir/compress/close before open" do
        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.add_data("This is hoge.txt content.", "hoge.txt") }.to raise_error(SevenZipRuby::InvalidOperation)

        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.mkdir("hoge/hoge") }.to raise_error(SevenZipRuby::InvalidOperation)

        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.compress }.to raise_error(SevenZipRuby::InvalidOperation)

        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.close }.to raise_error(SevenZipRuby::InvalidOperation)
      end

      example "add_data after close" do
        output = StringIO.new("")
        szw = SevenZipRuby::SevenZipWriter.new
        szw.open(output)
        szw.close
        expect{ szw.add_data("This is hoge.txt content.", "hoge.txt") }.to raise_error(SevenZipRuby::InvalidOperation)
      end

      example "clone and dup cannot be called." do
        expect{ SevenZipRuby::SevenZipWriter.new.clone }.to raise_error(NoMethodError)
        expect{ SevenZipRuby::SevenZipWriter.new.dup }.to raise_error(NoMethodError)
      end

      if (false && RUBY_ENGINE == "ruby")
        # It seems that Rubinius has the different way to handle error.
        # Therefore, it sometimes fails to kill SevenZipRuby thread.
        example "kill thread" do
          [ "LZMA", "PPMd", "BZIP2" ].each do |method|
            prc = lambda do
              output = StringIO.new("")
              SevenZipRuby::SevenZipWriter.open(output) do |szw|
                szw.method = method
                szw.level = 9
                szw.multi_thread = true
                szw.add_data(SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA * 3, "hoge.txt")
              end
            end

            start = Time.now
            th = Thread.start{ prc.call }
            th.join
            diff = Time.now - start

            20.times do
              kill_time = rand * diff
              th = Thread.start{ prc.call }
              sleep(kill_time)
              expect{ th.kill }.not_to raise_error   # Thread can be killed.
            end
          end
        end
      end

    end

  end

end
