# vim: tabstop=4 fileformat=linux fileencoding=utf-8 filetype=ruby

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

#		file.rewind
#			begin
#				SevenZipRuby::Reader.open( file, :password => "INCORRECT PASSWORD" ) do |szr|
#					first_file = szr.entries.select( &:file? ).first
#					assert_equal( fl, first_file.path )
#					assert_raise( SevenZipRuby::InvalidArchive ) do
#						data = szr.extract_data( first_file )
#						flunk( "The archive could be opened with an incollect password." )
#					end
#				end
#			rescue SevenZipRuby::InvalidOperation => err
#				# ignore
#			end

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
					flunk( "The archive could be opened with an incollect password." )
				end
			end

		file.rewind
			SevenZipRuby::Reader.open( file, :password => password ) do |szr|
				ent = szr.entries
				assert_equal( fl, ent[0].path )
			end

		file.close
	end

end



