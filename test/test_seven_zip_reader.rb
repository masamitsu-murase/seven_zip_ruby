# vim: tabstop=4 fileformat=linux fileencoding=utf-8 filetype=ruby

require 'rubygems'
# gem install test-unit
require 'test/unit'

STDERR.sync = true

$basedir = File.dirname( $0 )
$tmpdir = File.join( $basedir, "tmp" )
$resourcedir = File.join( $basedir, "res" )

require 'seven_zip_ruby'

class TestSevenZipReader < Test::Unit::TestCase

	def self.startup
		self.remove_tmpdir
	end

	def self.shutdown
		self.remove_tmpdir
	end

	def tmpdir
		unless File.exist?( $tmpdir )
			Dir.mkdir( $tmpdir ) rescue nil
		end
		$tmpdir
	end

	def self.remove_tmpdir
		if File.exist?( $tmpdir )
			Dir.rmdir( $tmpdir ) rescue nil
		end
	end

	def remove_tmp_entries( entries )
		entries.each do |f|
			pth = File.join( $tmpdir, f )
			File.delete( pth ) if File.exist?( pth )
		end
	end

	def test_reader_extract_data
		formats = [
			["7ZIP", "7z", "It's a 7z!\r\n"], 
		]
		formats.each do |e|
			type, ext, text, = *e
			pth = File.join( $resourcedir, "test_reader_data.#{ext}" )
			File.open( pth, "rb" ) do |file|
				SevenZipRuby::Reader.open( file, :type => type ) do |szr|
					first_file = szr.entries.select( &:file? ).first
					data = szr.extract_data( first_file )
					data.force_encoding( Encoding::UTF_8 )
					assert_equal( text, data )
				end
			end
		end
	end

	def test_reader_entries
		pth = File.join( $resourcedir, "test_reader_files.7z" )
		File.open( pth, "rb" ) do |file|
			SevenZipRuby::Reader.open( file ) do |szr|
				ent = szr.entries
				assert_equal( "The Flying Spaghetti Monster.txt", ent[0].path )
				assert_equal( "The Three Little Pigs.txt", ent[1].path )
			end
		end
	end

	def test_reader_extract
		tmp = tmpdir()

		entries = [
			"The Flying Spaghetti Monster.txt", 
			"The Three Little Pigs.txt"
		]
		remove_tmp_entries( entries )

		pth = File.join( $resourcedir, "test_reader_files.7z" )
		File.open( pth, "rb" ) do |file|
			SevenZipRuby::Reader.open( file ) do |szr|
				szr.extract_all( tmp )
			end
		end

		entries.each do |f|
			pth = File.join( tmp, f )
			assert( File.exist?( pth ) )
		end

		remove_tmp_entries( entries )
	end

	def test_reader_filepath_encoding_cp932
		tmp = tmpdir()

		pth = File.join( $resourcedir, "test_reader_filename_cp932.7z" )
		File.open( pth, "rb" ) do |file|
			SevenZipRuby::Reader.open( file ) do |szr|
				ent = szr.entries
				assert_equal( "石肥三年.txt", ent[0].path )
				szr.extract_all( tmp )
			end
		end
		assert( File.exist?( File.join( tmp, "石肥三年.txt" ) ) )

		remove_tmp_entries( ["石肥三年.txt"] )
	end

end


