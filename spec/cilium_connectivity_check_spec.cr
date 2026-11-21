require "./routing_spec_helper"
require "../src/kubernetes/software/cilium"

# Runs the generated cross-node connectivity script against a stubbed kubectl, so the
# pod MTU comparison is exercised rather than only rendered.
private module ConnectivityCheckHarness
  extend self

  STUBS = <<-'BASH'
    kubectl() {
      case "$*" in
        "get nodes --no-headers -l "*)
          echo "node-a Ready"
          echo "node-b Ready"
          ;;
        "-n kube-system rollout status ds cilium"*) return 0 ;;
        "wait --for=condition=Ready nodes --all"*) return 0 ;;
        "apply -f -") cat > /dev/null ;;
        "-n kube-system wait --for=condition=Ready"*) return 0 ;;
        "-n kube-system get pod "*"-o jsonpath="*) echo "10.0.0.2" ;;
        "-n kube-system exec "*" -- sh -c "*)
          echo "1450"
          echo "10.0.0.2 via 10.0.0.1 dev eth0 src 10.0.0.9 uid 0"
          echo "    cache mtu $TEST_POD_MTU"
          ;;
        "-n kube-system exec "*" -- ping -c 3 -W 2 -M do -s "*)
          if [ "${TEST_PING_DF:-ok}" = ok ]; then
            echo "3 packets transmitted, 3 received, 0% packet loss"
          else
            echo "3 packets transmitted, 0 received, 100% packet loss" >&2
            return 1
          fi
          ;;
        "-n kube-system exec "*" -- ping "*) echo "3 packets transmitted, 3 received, 0% packet loss" ;;
        "-n kube-system delete pod "*) return 0 ;;
        *) echo "unexpected kubectl call: $*" >&2; return 1 ;;
      esac
    }
    BASH

  record Outcome, output : String, success : Bool

  def run(expected_pod_mtu : Int32, pod_mtu : Int32, ping_df : Bool = true) : Outcome
    prelude = <<-BASH
      namespace=kube-system
      image=nicolaka/netshoot:v0.16
      timeout_seconds=300
      expected_pod_mtu=#{expected_pod_mtu}
      BASH

    output = IO::Memory.new
    script = [STUBS, prelude, Kubernetes::Software::Cilium::CONNECTIVITY_CHECK_SCRIPT].map(&.strip).join("\n\n")
    status = Process.run("bash", ["-c", script],
      env: {"TEST_POD_MTU" => pod_mtu.to_s, "TEST_PING_DF" => ping_df ? "ok" : "drop"},
      output: output, error: output)
    Outcome.new(output.to_s, status.success?)
  end
end

describe "Cilium connectivity check script" do
  it "passes when the pod MTU matches the configured one" do
    outcome = ConnectivityCheckHarness.run(expected_pod_mtu: 1320, pod_mtu: 1320)

    outcome.success.should be_true
    outcome.output.should contain("validation passed")
    outcome.output.should contain("1320-byte (pod MTU) ping")
  end

  it "fails when pods use a smaller MTU than the configuration implies" do
    outcome = ConnectivityCheckHarness.run(expected_pod_mtu: 1370, pod_mtu: 1320)

    outcome.success.should be_false
    outcome.output.should contain("uses a pod MTU of 1320")
    outcome.output.should contain("implies 1370")
    outcome.output.should contain("did not apply the configured MTU")
    outcome.output.should contain("rollout restart ds cilium")
    outcome.output.should_not contain("validation passed")
  end

  it "fails when pods use a larger MTU than the configuration implies" do
    outcome = ConnectivityCheckHarness.run(expected_pod_mtu: 1320, pod_mtu: 1400)

    outcome.success.should be_false
    outcome.output.should contain("uses a pod MTU of 1400")
    outcome.output.should contain("implies 1320")
  end

  it "does not compare when Cilium auto-detects the MTU" do
    outcome = ConnectivityCheckHarness.run(expected_pod_mtu: 0, pod_mtu: 1450)

    outcome.success.should be_true
    outcome.output.should contain("1450-byte (pod MTU) ping")
  end

  it "fails when packets of the pod MTU are dropped" do
    outcome = ConnectivityCheckHarness.run(expected_pod_mtu: 1320, pod_mtu: 1320, ping_df: false)

    outcome.success.should be_false
    outcome.output.should contain("Packets of the pod MTU are dropped")
  end
end
