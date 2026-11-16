require "json"
require "retriable"
require "tasker"
require "../util"
require "./prefixed_io"
require "./shell"

class Util::SSH
  include ::Util
  include ::Util::Shell

  # Default SSH connection timeout in seconds
  DEFAULT_CONNECT_TIMEOUT = 15
  # Default SSH command timeout in seconds
  DEFAULT_COMMAND_TIMEOUT = 30
  # Default number of retry attempts
  DEFAULT_MAX_ATTEMPTS = 20
  # Default delay between retries in seconds
  DEFAULT_RETRY_DELAY = 5

  # How long the parsed `tailscale status` output is reused. Every SSH command
  # resolves the host, so without this the CLI would run dozens to hundreds of
  # times during a single `create`.
  TAILSCALE_STATUS_CACHE_TTL = 5.seconds

  # The local machine cannot use the tailnet at all: CLI missing, daemon not
  # running, not signed in, or unparseable status. Retrying cannot fix it, so
  # this is not an IO::Error and is not retried.
  class TailscaleError < Exception
  end

  # The node has not registered with the tailnet yet. Expected during first
  # boot, so this is an IO::Error and is retried by wait_for_instance.
  class TailscaleNotReady < IO::Error
  end

  @@tailscale_status_mutex = Mutex.new
  @@tailscale_status_cache : Tuple(Time::Span, String?)? = nil

  getter private_ssh_key_path : String
  getter public_ssh_key_path : String
  getter prefer_private_ip : Bool = false
  getter user : String = "root"
  getter tailscale_hostname_suffix : String = ""

  def initialize(@private_ssh_key_path, @public_ssh_key_path = "", @prefer_private_ip = false, @user = "root", @tailscale_hostname_suffix = "")
  end

  def self.calculate_fingerprint(public_ssh_key_path)
    private_key = File.read(public_ssh_key_path).split[1]
    Digest::MD5.hexdigest(Base64.decode(private_key)).chars.each_slice(2).map(&.join).join(":")
  end

  # Wait for an instance to be ready by repeatedly running a test command until it returns the expected result
  # Raised when the wait below runs out of attempts, carrying the reason of the last try so an auth
  # failure is not reported as slowness.
  class WaitTimeout < Exception
  end

  def wait_for_instance(
    instance,
    port,
    use_ssh_agent,
    test_command,
    expected_result,
    max_attempts : Int32 = DEFAULT_MAX_ATTEMPTS,
    retry_delay : Time::Span = DEFAULT_RETRY_DELAY.seconds
  )
    result_str = ""
    debug = ENV.fetch("DEBUG", "false") == "true"
    started = Time.monotonic
    last_error = "no attempt made"

    max_attempts.times do |attempt|
      begin
        Tasker.timeout(DEFAULT_COMMAND_TIMEOUT.seconds) do
          result_str = run(instance, port, test_command, use_ssh_agent, false).to_s.strip.gsub(/[\r\n]+/, "\n")
        end

        if debug
          puts "SSH command result: ===#{result_str}==="
          puts "SSH command expected: ===#{expected_result}==="
          puts "Matching?: ===#{result_str == expected_result}==="
        end

        return result_str if result_str == expected_result

        last_error = "the command output was #{result_str.inspect}"
      rescue ex : Tasker::Timeout
        last_error = "the SSH command timed out after #{DEFAULT_COMMAND_TIMEOUT} seconds"
      rescue ex : IO::Error
        last_error = ex.message.to_s
      end

      log_line "Instance #{instance.name} not ready after #{(Time.monotonic - started).total_seconds.round}s, attempt #{attempt + 1}/#{max_attempts}: #{last_error}",
        log_prefix: "Instance #{instance.name}"

      sleep retry_delay unless attempt == max_attempts - 1
    end

    raise WaitTimeout.new(
      "Instance #{instance.name} was not reachable over SSH after #{max_attempts} attempts " \
      "(#{(Time.monotonic - started).total_seconds.round}s): #{last_error}"
    )
  end

  # Run a command on a remote instance via SSH
  def run(instance, port, command, use_ssh_agent, print_output = true, disable_log_prefix = false, capture_output = false)
    host = resolve_host(instance)

    debug = ENV.fetch("DEBUG", "false") == "true"
    log_level = debug ? "DEBUG" : "ERROR"

    ssh_args = build_ssh_args(
      host_ip_address: host,
      port: port,
      command: command,
      use_ssh_agent: use_ssh_agent,
      log_level: log_level
    )

    stdout = IO::Memory.new
    stderr = IO::Memory.new

    # Setup output streams based on capture mode
    output_streams = if capture_output
                       {
                         out: stdout,
                         err: stderr,
                       }
                     else
                       setup_output_streams(instance.name, stdout, stderr, print_output, debug, disable_log_prefix)
                     end

    # Run the SSH command
    status = Process.run("ssh",
      args: ssh_args,
      output: output_streams[:out],
      error: output_streams[:err]
    )

    # Handle errors consistently
    unless status.success?
      error_msg = stderr.to_s.strip
      log_line "SSH command failed (exit code: #{status.exit_code}): #{error_msg}",
        log_prefix: "Instance #{instance.name}" if debug
      raise IO::Error.new("SSH command failed on #{instance.name}: #{error_msg}")
    end

    # Return captured output
    stdout.to_s.strip
  end

  private def build_ssh_args(host_ip_address, port, command, use_ssh_agent, log_level)
    args = [
      "-o", "ConnectTimeout=#{DEFAULT_CONNECT_TIMEOUT}",
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "BatchMode=yes",
      "-o", "LogLevel=#{log_level}",
      "-o", "ServerAliveInterval=10",
      "-o", "ServerAliveCountMax=3",
      "-o", "PasswordAuthentication=no",
      "-o", "PreferredAuthentications=publickey",
      "-o", "PubkeyAuthentication=yes",
    ]

    # Add private key if not using SSH agent
    unless use_ssh_agent
      args.concat(["-i", private_ssh_key_path])
    end

    # Add port, user@host, and command
    args.concat(["-p", port.to_s, "--", "#{@user}@#{host_ip_address}", command])

    args
  end

  private def setup_output_streams(instance_name, stdout, stderr, print_output, debug, disable_log_prefix)
    if print_output || debug
      if disable_log_prefix
        {
          out: IO::MultiWriter.new(STDOUT, stdout),
          err: IO::MultiWriter.new(STDERR, stderr),
        }
      else
        {
          out: IO::MultiWriter.new(PrefixedIO.new("[Instance #{instance_name}] ", STDOUT), stdout),
          err: IO::MultiWriter.new(PrefixedIO.new("[Instance #{instance_name}] ", STDERR), stderr),
        }
      end
    else
      {
        out: stdout,
        err: stderr,
      }
    end
  end

  private def default_log_prefix
    "+"
  end

  private def tailscale? : Bool
    !tailscale_hostname_suffix.empty?
  end

  private def resolve_host(instance)
    return resolve_ip_host(instance) unless tailscale?

    resolve_tailscale_host(instance)
  end

  private def resolve_tailscale_host(instance)
    hostname = instance.tailscale_host(tailscale_hostname_suffix)
    status = tailscale_status

    unless status
      raise TailscaleError.new(
        "Cannot read the tailnet on this machine: the `tailscale` CLI is missing, tailscaled is not running, or you are not signed in. " \
        "Install Tailscale and run `tailscale up` before using networking.tailscale."
      )
    end

    json = JSON.parse(status)
    backend_state = json["BackendState"]?.try(&.as_s?)

    if backend_state != "Running"
      raise TailscaleError.new(
        "This machine is not connected to a tailnet (BackendState: #{backend_state || "unknown"}). Run `tailscale up` and retry."
      )
    end

    peer = find_tailscale_peer(json, hostname)

    unless peer
      raise TailscaleNotReady.new(
        "Tailscale peer #{hostname} is not in the tailnet yet. If the node has finished booting, " \
        "check networking.tailscale.hostname_suffix, the auth key and the tailnet ACLs."
      )
    end

    unless peer["Online"]?.try(&.as_bool?) == true
      raise TailscaleNotReady.new("Tailscale peer #{hostname} is registered but not online yet")
    end

    hostname
  rescue JSON::ParseException | TypeCastError | KeyError
    raise TailscaleError.new("Could not parse the output of `tailscale status --json`")
  end

  private def find_tailscale_peer(json : JSON::Any, hostname : String) : JSON::Any?
    peers = json["Peer"]?.try(&.as_h?)
    return nil unless peers

    peers.each do |_key, peer|
      dns_name = peer["DNSName"]?.try(&.as_s?)
      next unless dns_name
      # Tailscale reports MagicDNS names with a trailing dot.
      return peer if dns_name.chomp(".") == hostname
    end

    nil
  end

  private def resolve_ip_host(instance)
    host_ip_address = instance.host_ip_address(prefer_private_ip)
    raise "Instance #{instance.name} has no IP address" unless host_ip_address

    if prefer_private_ip && instance.private_net.try(&.first?).try(&.ip).nil?
      log_line "WARNING: Instance #{instance.name} has no private IP, falling back to public IP", log_prefix: "Instance #{instance.name}"
    end

    host_ip_address
  end

  private def tailscale_status : String?
    now = Time.monotonic

    @@tailscale_status_mutex.synchronize do
      if cached = @@tailscale_status_cache
        return cached[1] if now - cached[0] < TAILSCALE_STATUS_CACHE_TTL
      end
    end

    output = `tailscale status --json 2>/dev/null`
    result = $?.success? ? output : nil

    @@tailscale_status_mutex.synchronize do
      @@tailscale_status_cache = {Time.monotonic, result}
    end

    result
  end
end
