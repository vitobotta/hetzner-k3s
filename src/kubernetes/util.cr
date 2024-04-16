module Kubernetes::Util
  def apply_manifest(yaml = "", url = "", prefix = "", error_message = "")
    return if yaml.blank? && url.blank?

    command = if yaml.blank?
      "kubectl apply -f #{url}"
    else
      <<-BASH
      kubectl apply -f - <<-EOF
      #{yaml}
      EOF
      BASH
    end

    result = ::Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token, prefix)

    unless result.success?
      puts "[#{prefix}] #{error_message}: #{result.output}"
      exit 1
    end
  end

  def apply_kubectl_command(command, prefix = "", error_message = "")
    result = ::Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token, prefix: prefix)

    unless result.success?
      puts "[#{prefix}] #{error_message}: #{result.output}"
      exit 1
    end
  end
end
