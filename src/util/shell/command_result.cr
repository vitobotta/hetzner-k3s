class Util::Shell::CommandResult
  getter output : String
  getter status : Int32

  def initialize(@output, @status)
  end

  def success?
    status.zero?
  end
end
