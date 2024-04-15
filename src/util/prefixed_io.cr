class PrefixedIO < IO
  def initialize(@prefix : String, @io : IO); end

  def read(slice : Bytes)
    raise NotImplementedError.new "#read"
  end

  def write(slice : Bytes) : Nil
    content = String.new(slice)
    lines = content.lines
    lines.each do |line|
      @io << @prefix << "#{line}\n"
    end
  end
end
