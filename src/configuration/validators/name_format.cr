# Naming rules shared by the cluster name and the node pool names. Both end up in
# Hetzner server names, which must be valid hostnames, so they are restricted to
# lowercase letters, digits and dashes.
module Configuration::Validators::NameFormat
  ALLOWED_CHARACTERS_DESCRIPTION = "only lowercase letters, digits and dashes are allowed"

  def self.allowed_characters?(name : String) : Bool
    name.matches?(/\A[a-z\d-]+\z/)
  end

  def self.starts_and_ends_correctly?(name : String) : Bool
    name.matches?(/\A[a-z]([a-z\d-]*[a-z\d])?\z/)
  end

  # Pool names also appear inside a server name (`<cluster>-pool-8gb-worker1`), never on their own, so
  # a leading digit is fine there. A pool called `8gb` or `2xl-fsn` worked before validation existed
  # and keeps working.
  def self.pool_starts_and_ends_correctly?(name : String) : Bool
    name.matches?(/\A[a-z\d]([a-z\d-]*[a-z\d])?\z/)
  end

  def self.valid?(name : String) : Bool
    allowed_characters?(name) && starts_and_ends_correctly?(name)
  end

  def self.pool_valid?(name : String) : Bool
    allowed_characters?(name) && pool_starts_and_ends_correctly?(name)
  end
end
