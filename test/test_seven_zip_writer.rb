# vim: tabstop=4 fileformat=unix fileencoding=utf-8 filetype=ruby

require 'rubygems'
# gem install test-unit
require 'test/unit'

STDERR.sync = true

$basedir = File.dirname( $0 )
$tmpdir = File.join( $basedir, "tmp" )
$resourcedir = File.join( $basedir, "res" )

#gem 'seven_zip_ruby_am', '< 1.2.6'
require 'seven_zip_ruby'
require 'stringio'

class TestSevenZipWriter < Test::Unit::TestCase

	def test_writer_files
		entries = [
			"The Flying Spaghetti Monster.txt", 
			"The Three Little Pigs.txt", 
			"石肥三年.txt"
		]

		file = StringIO.new( "test_writer_files.7z", "w+b" )
			SevenZipRuby::Writer.open( file ) do |szw|
				Dir.chdir( $resourcedir ) do |dummy|
					entries.each do |e|
						szw.add_file( e )
					end
				end
			end

		file.rewind
			SevenZipRuby::Reader.open( file ) do |szr|
				ent = szr.entries
				assert_equal( entries.size, ent.size )
				assert_equal( entries[0], ent[0].path )
				assert_equal( entries[1], ent[1].path )
				assert_equal( entries[2], ent[2].path )
			end

		file.close
	end

	def test_writer_encrypt
		require 'digest/md5'
		password = Random.rand
		notify( "Random.rand: #{password}" )
		password = Digest::MD5.digest( password.to_s )
		password = [password].pack( "m0" )	# base64

		fl = "The Three Little Pigs.txt"

		file = StringIO.new( "test_writer_crypt.7z", "w+b" )
			SevenZipRuby::Writer.open( file, :password => password ) do |szw|
				Dir.chdir( $resourcedir ) do |dummy|
					szw.add_file( fl )
				end
			end

		file.rewind
			SevenZipRuby::Reader.open( file ) do |szr|
				first_file = szr.entries.select( &:file? ).first
				assert_equal( fl, first_file.path )
				assert_raise( StandardError ) do
					data = szr.extract_data( first_file )
					flunk( "The archive could be opened without a password." )
				end
			end

		file.rewind
			begin
				SevenZipRuby::Reader.open( file, :password => "INCORRECT PASSWORD" ) do |szr|
					first_file = szr.entries.select( &:file? ).first
					assert_equal( fl, first_file.path )
					# 7z 19.00 throws SevenZipRuby::InvalidArchive.
					assert_raise( SevenZipRuby::InvalidArchive ) do
						data = szr.extract_data( first_file )
						# p7zip 16.02 returns nil.
						raise SevenZipRuby::InvalidArchive.new if data.nil?
						flunk( "The archive could be opened with an incorrect password." )
					end
				end
			rescue SevenZipRuby::InvalidOperation => err
				# ignore
			end

		file.rewind
			SevenZipRuby::Reader.open( file, :password => password ) do |szr|
				ent = szr.entries
				assert_equal( fl, ent[0].path )
			end

		file.close
	end

	def test_writer_encrypt_header
		require 'digest/md5'
		password = Random.rand
		notify( "Random.rand: #{password}" )
		password = Digest::MD5.digest( password.to_s )
		password = [password].pack( "m0" )	# base64


		fl = "The Three Little Pigs.txt"

		file = StringIO.new( "test_writer_crypt.7z", "w+b" )
			SevenZipRuby::Writer.open( file, :password => password ) do |szw|
				szw.header_encryption = true
				Dir.chdir( $resourcedir ) do |dummy|
					szw.add_file( fl )
				end
			end

		file.rewind
			# StandardError: Invalid file format. open
			assert_raise( StandardError ) do
				SevenZipRuby::Reader.open( file ) do |szr|
					flunk( "The archive could be opened without a password." )
				end
			end

		file.rewind
			# StandardError: Invalid file format. open
			assert_raise( StandardError ) do
				SevenZipRuby::Reader.open( file, :password => "INCORRECT PASSWORD" ) do |szr|
					flunk( "The archive could be opened with an incorrect password." )
				end
			end

		file.rewind
			SevenZipRuby::Reader.open( file, :password => password ) do |szr|
				ent = szr.entries
				assert_equal( fl, ent[0].path )
			end

		file.close
	end

	def test_writer_levels
		fl = '石肥三年.txt'
		pth = File.join( $resourcedir, fl )
		data = File.read( pth, :encoding => Encoding::UTF_8 )

		["LZMA", "LZMA2", "PPMd", "BZIP2", "DEFLATE"].each do |method|
			[0, 1, 3, 5, 7, 9].each do |level|
				msg = "method: #{method}, level: #{level}."
				__test_writer_levels_compress( fl, data, method, level, msg )
			end
		end
	end

	def __test_writer_levels_compress( i_name, i_data, i_method, i_level, i_message )
		file = StringIO.new( "test_writer_levels.7z", "w+b" )
			SevenZipRuby::Writer.open( file ) do |szw|
				szw.method = i_method
#				szw.multi_thread = true
				szw.level = i_level

				d = i_data.dup
				szw.add_data( d, i_name )
				szw.compress
				d.replace( "\0" * d.size )
			end

		file.rewind
			SevenZipRuby::Reader.open( file ) do |szr|
				first_file = szr.entries.select( &:file? ).first
				assert_equal( i_name, first_file.path, i_message )

				d = szr.extract_data( first_file )
				d.force_encoding( i_data.encoding )
				assert_equal( i_data, d, i_message )
			end

		file.close
	end

end



