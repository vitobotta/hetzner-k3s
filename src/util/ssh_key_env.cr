require "digest/sha256"

class SshKeyEnvError < Exception; end

# Resolves the cluster SSH key pair from environment variables, so an unattended run (CI) does not
# have to write key files before invoking the CLI.
#
# SSH_PRIVATE_KEY and SSH_PUBLIC_KEY hold the key material itself. Content is written under
# ~/.hetzner-k3s/ssh with a content-derived name and 0600 permissions, and the returned paths are
# used wherever a path is expected, which keeps fingerprints, the Hetzner key upload and every ssh
# invocation unchanged. When only the private key is provided, the public key is derived with
# ssh-keygen. Values are normalised for the usual CI pitfalls: escaped newlines instead of real
# ones, indentation, and a missing trailing newline.
module Util::SSHKeyEnv
  PRIVATE_KEY_VAR = "SSH_PRIVATE_KEY"
  PUBLIC_KEY_VAR  = "SSH_PUBLIC_KEY"
  DIRECTORY       = "~/.hetzner-k3s/ssh"
  FILE_MODE       = 0o600

  PRIVATE_KEY_HEADER = /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/
  PUBLIC_KEY_PREFIX  = /\A(ssh-|ecdsa-|sk-ssh-|sk-ecdsa-)/

  @@private_key_path : String?
  @@public_key_path : String?

  def self.private_key? : Bool
    !private_key_content.nil?
  end

  def self.public_key? : Bool
    !public_key_content.nil?
  end

  def self.private_key_content : String?
    normalize(ENV[PRIVATE_KEY_VAR]?)
  end

  def self.public_key_content : String?
    normalize(ENV[PUBLIC_KEY_VAR]?)
  end

  def self.valid_private_key_format? : Bool
    content = private_key_content
    !content.nil? && content.matches?(PRIVATE_KEY_HEADER)
  end

  def self.valid_public_key_format? : Bool
    content = public_key_content
    !content.nil? && content.matches?(PUBLIC_KEY_PREFIX) && content.split(' ').size >= 2
  end

  def self.private_key_path : String?
    key = private_key_content
    return nil unless key

    @@private_key_path ||= write("id_#{digest(key)}", key)
  end

  def self.public_key_path : String?
    key = public_key_content
    return nil unless key || private_key?

    @@public_key_path ||= key ? write("id_#{digest(key)}.pub", key) : derive_public_key
  end

  # Specs change HOME and the variables, and production never does. Memoisation keeps the paths
  # stable for the process lifetime.
  def self.reset! : Nil
    @@private_key_path = nil
    @@public_key_path = nil
  end

  private def self.derive_public_key : String
    private_path = private_key_path.not_nil!
    path = "#{private_path}.pub"
    return path if File.exists?(path)

    output = IO::Memory.new
    errors = IO::Memory.new

    status = begin
      Process.run("ssh-keygen", ["-y", "-f", private_path], output: output, error: errors)
    rescue File::NotFoundError
      raise SshKeyEnvError.new("ssh-keygen is required to derive a public key from #{PRIVATE_KEY_VAR}")
    end

    unless status.success?
      raise SshKeyEnvError.new("Could not derive a public key from #{PRIVATE_KEY_VAR}: #{errors.to_s.strip}")
    end

    write(File.basename(path), output.to_s)
  end

  private def self.write(name : String, content : String) : String
    directory = directory_path
    Dir.mkdir_p(directory, 0o700)

    path = File.join(directory, name)
    File.write(path, content) unless File.exists?(path) && File.read(path) == content
    File.chmod(path, FILE_MODE)

    path
  end

  private def self.directory_path : String
    home = ENV["HOME"]? || raise SshKeyEnvError.new("HOME environment variable not set")
    File.expand_path(DIRECTORY.sub("~/", "#{home}/"))
  end

  private def self.digest(content : String) : String
    Digest::SHA256.hexdigest(content)[0, 16]
  end

  private def self.normalize(value : String?) : String?
    return nil if value.nil?

    normalized = value.strip
    return nil if normalized.empty?

    normalized = normalized.gsub("\\n", "\n") unless normalized.includes?('\n')
    normalized = "#{normalized}\n" unless normalized.ends_with?('\n')

    normalized
  end
end
