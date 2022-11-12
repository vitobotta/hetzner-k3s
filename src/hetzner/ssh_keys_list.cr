require "./ssh_key"

class Hetzner::SSHKeysList
  include JSON::Serializable

  property ssh_keys : Array(Hetzner::SSHKey)
end
