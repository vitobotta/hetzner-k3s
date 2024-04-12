class PrefixedIO < IO
  def initialize(@prefix : String, @io : IO); end

  def read(slice : Bytes)
    raise NotImplementedError.new "#read"
  end

  def write(slice : Bytes) : Nil
    @io.print @prefix
    slice.each do |byte|
      @io.write_byte byte
      @io.print @prefix if 10 == byte
    end
  end
end
