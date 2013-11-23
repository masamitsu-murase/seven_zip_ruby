require("seven_zip_ruby")
require_relative("seven_zip_ruby_spec_helper")

describe SevenZipRuby do
  before(:all) do
    SevenZipRubySpecHelper.prepare
    # GC.stress = true
  end

  after(:all) do
    # GC.stress = false
    SevenZipRubySpecHelper.cleanup
  end


  describe SevenZipRuby::SevenZipReader do

    example "get entry information in the archive" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        szr = SevenZipRuby::SevenZipReader.new
        szr.open(file)
        entries = szr.entries

        expect(entries.size).to be SevenZipRubySpecHelper::SAMPLE_DATA.size

        SevenZipRubySpecHelper::SAMPLE_DATA.each do |sample|
          entry = entries.select{ |i| i.path == Pathname(sample[:name]).cleanpath }
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
          expect(info.method).to eq "LZMA"
          expect(info.phy_size).to be file.size
          expect(info.solid?).to be_true
        end
      end
    end

    example "extract data directly from archive" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        SevenZipRuby::SevenZipReader.open(file) do |szr|
          entries = szr.entries

          SevenZipRubySpecHelper::SAMPLE_DATA.each do |sample|
            entry = entries.find{ |i| i.path == Pathname(sample[:name]).cleanpath }
            expect(szr.extract_data(entry.index)).to eq sample[:data]
          end
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

    example "run in another thread" do
      File.open(SevenZipRubySpecHelper::SEVEN_ZIP_FILE, "rb") do |file|
        szr = nil
        sample = nil
        entry = nil
        th = Thread.new do
          szr = SevenZipRuby::SevenZipReader.open(file)
          sample = SevenZipRubySpecHelper::SAMPLE_DATA.sample
          entry = szr.entries.find{ |i| i.path == Pathname(sample[:name]).cleanpath }
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

      data[0x27] = 0xEB.chr  # This highly dependes on the current test binary.
      SevenZipRuby::SevenZipReader.open(StringIO.new(data)) do |szr|
        expect(szr.test).to eq false
        expect(szr.verify_detail).to eq [ :DataError, :DataError, :DataError, true, true, true ]
      end


      data = File.open(SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD_FILE, "rb", &:read)
      SevenZipRuby::SevenZipReader.open(StringIO.new(data), { password: SevenZipRubySpecHelper::SEVEN_ZIP_PASSWORD }) do |szr|
        expect(szr.verify).to eq true
      end

      SevenZipRuby::SevenZipReader.open(StringIO.new(data), { password: "wrong password" }) do |szr|
        expect(szr.verify).to eq false
      end

      SevenZipRuby::SevenZipReader.open(StringIO.new(data), { password: "wrong password" }) do |szr|
        expect(szr.verify_detail).to eq [ :DataError, :DataError, :DataError, true, true, true ]
      end
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


        th = Thread.start do
          SevenZipRuby::SevenZipWriter.open(output) do |szw|
            szw.method = "BZIP2"
            szw.level = 9
            szw.multi_thread = false
            szw.add_buffer("hoge.txt", SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA * 2)
          end
        end

        sleep 0.1  # Highly dependes on CPU speed...
        expect{ th.kill }.not_to raise_error # Thread can be killed.
      end

    end

  end


  describe SevenZipRuby::SevenZipWriter do

    example "compress without block" do
      output = StringIO.new("")
      szw = SevenZipRuby::SevenZipWriter.new
      szw.open(output)
      szw.add_buffer("hoge.txt", "This is hoge.txt.")
      szw.add_buffer("hoge2.txt", "This is hoge2.txt.")
      szw.mkdir("hoge/hoge/hoge")
      szw.compress
      szw.close
      output.close
    end

    example "compress" do
      output = StringIO.new("")
      SevenZipRuby::SevenZipWriter.open(output) do |szw|
        szw.add_buffer("hoge.txt", "This is hoge.txt.")
        szw.add_buffer("hoge2.txt", "This is hoge2.txt.")
        szw.mkdir("hoge/hoge/hoge")
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

    example "add_directory" do
      Dir.chdir(SevenZipRubySpecHelper::SAMPLE_FILE_DIR) do
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          Pathname.glob("*") do |path|
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
            if (entry_in_sample[:directory])
              expect(entry.directory?).to eq true
            else
              expect(szr.extract_data(entry)).to eq File.open(entry_in_sample[:name], "rb", &:read)
            end
          end
        end
      end
    end

    example "use various methods" do
      [ "COPY", "DEFLATE", "LZMA", "LZMA2", "BZIP2", "PPMd" ].each do |type|
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          szw.method = type
          szw.add_buffer("hoge.txt", SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA)
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
          szw.add_buffer("hoge1.txt", data)
          szw.add_buffer("hoge2.txt", data + data.slice(1 .. -1))
          szw.add_buffer("hoge3.txt", data + data.reverse + data.slice(1 .. -1))
        end
        next output.string.size
      end
      size.each_cons(2) do |large, small|
        expect(large - small >= -1).to eq true
      end
    end

    example "set solid" do
      size = [ false, true ].map do |solid|
        output = StringIO.new("")
        SevenZipRuby::SevenZipWriter.open(output) do |szw|
          szw.solid = solid
          data = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
          szw.add_buffer("hoge1.txt", data)
          szw.add_buffer("hoge2.txt", data + data.slice(1 .. -1))
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
            szw.add_buffer("hoge#{i}.txt", data)
          end
        end
        next output.string.size
      end
      expect(size.sort.reverse).to eq size
    end

    if (SevenZipRubySpecHelper.processor_count > 1)
      example "set multi_thread" do
        time = [ false, true ].map do |multi_thread|
          output = StringIO.new("")
          start = nil
          SevenZipRuby::SevenZipWriter.open(output) do |szw|
            szw.method = "BZIP2"  # BZIP2 uses multi threads.
            szw.multi_thread = multi_thread
            data = SevenZipRubySpecHelper::SAMPLE_LARGE_RANDOM_DATA
            szw.add_buffer("hoge.txt", data * 10)
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
        expect{ SevenZipRuby::SevenZipWriter.open(StringIO.new("")).method = "Unknown" }.to raise_error
      end

      example "invalid level" do
        expect{ SevenZipRuby::SevenZipWriter.open(StringIO.new("")).level = 2 }.to raise_error
      end

      example "add_buffer/mkdir/compress/close before open" do
        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.add_buffer("hoge.txt", "This is hoge.txt.") }.to raise_error(SevenZipRuby::InvalidOperation)

        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.mkdir("hoge/hoge") }.to raise_error(SevenZipRuby::InvalidOperation)

        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.compress }.to raise_error(SevenZipRuby::InvalidOperation)

        szw = SevenZipRuby::SevenZipWriter.new
        expect{ szw.close }.to raise_error(SevenZipRuby::InvalidOperation)
      end

      example "add_buffer after close" do
        output = StringIO.new("")
        szw = SevenZipRuby::SevenZipWriter.new
        szw.open(output)
        szw.close
        expect{ szw.add_buffer("hoge.txt", "This is hoge.txt.") }.to raise_error(SevenZipRuby::InvalidOperation)
      end

    end

  end

end

