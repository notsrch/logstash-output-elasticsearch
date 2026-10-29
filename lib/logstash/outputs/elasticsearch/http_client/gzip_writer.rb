require 'java'

module LogStash; module Outputs; class ElasticSearch; class HttpClient;
  # Writes a gzip stream (RFC 1952) to a Ruby IO with the JDK's java.util.zip.
  #
  # JRuby implements Zlib::GzipWriter with JZlib, a pure-Java port of zlib.
  # java.util.zip uses the zlib library that ships with the JDK and a CRC32
  # that the JIT compiles to CPU instructions, so the same compression level
  # needs less CPU. The output is ordinary gzip at the same level.
  #
  # It implements the methods that HttpClient#bulk calls, with the behavior of
  # Zlib::GzipWriter:
  # * #write(string) compresses the bytes of the string and returns their count.
  # * #pos is the number of uncompressed bytes written, also after #close.
  # * #flush sync-flushes the compressed data written so far to the IO.
  # * #close writes the gzip trailer, closes the IO and returns it.
  class GzipWriter
    BUFFER_SIZE = 64 * 1024
    # ID1, ID2, CM (deflate), FLG, MTIME (4 bytes, not set), XFL, OS (unknown)
    HEADER = [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff].pack("C*").to_java_bytes

    attr_reader :pos

    def initialize(io, level)
      @io = io
      @pos = 0
      @crc = java.util.zip.CRC32.new
      # nowrap: raw deflate data; this class writes the gzip header and trailer
      @deflater = java.util.zip.Deflater.new(level, true)
      @buffer = java.io.ByteArrayOutputStream.new(BUFFER_SIZE)
      # syncFlush: #flush emits all pending data, like Zlib::SYNC_FLUSH
      @deflater_stream = java.util.zip.DeflaterOutputStream.new(@buffer, @deflater, BUFFER_SIZE, true)
      @buffer.write(HEADER, 0, HEADER.length)
    end

    def write(string)
      bytes = string.to_java_bytes
      @crc.update(bytes, 0, bytes.length)
      @deflater_stream.write(bytes, 0, bytes.length)
      @pos += bytes.length
      bytes.length
    end

    def flush
      @deflater_stream.flush
      drain
      self
    end

    def close
      @deflater_stream.finish
      @deflater.end
      trailer = [@crc.value, @pos & 0xffffffff].pack("VV").to_java_bytes
      @buffer.write(trailer, 0, trailer.length)
      drain
      @io.close
      @io
    end

    private

    def drain
      return if @buffer.size.zero?
      @io.write(String.from_java_bytes(@buffer.to_byte_array))
      @buffer.reset
    end
  end
end; end; end; end
