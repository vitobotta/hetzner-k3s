require "./routing_spec_helper"
require "../src/hetzner/instance/create"

describe "instance creation retry delay" do
  it "doubles up to the cap and stays there" do
    [1, 2, 3, 4, 5, 6, 7, 8].map { |attempt| Hetzner::Instance::Create.retry_delay_seconds(attempt) }
      .should eq([1_i64, 2_i64, 4_i64, 8_i64, 16_i64, 32_i64, 60_i64, 60_i64])
  end

  it "does not overflow Int32 or Int64 on a long run of retries" do
    [32, 33, 62, 63, 64, 65, 1000].each do |attempt|
      Hetzner::Instance::Create.retry_delay_seconds(attempt).should eq(60_i64)
    end
  end

  it "never returns a delay below the initial one" do
    Hetzner::Instance::Create.retry_delay_seconds(0).should eq(1_i64)
  end
end

describe "invalid input detection" do
  it "recognises a compact Hetzner error body" do
    body = %({"error":{"code":"invalid_input","message":"unsupported location for server type"}})
    Hetzner::Instance::Create.invalid_input?(body).should be_true
  end

  it "recognises a pretty printed body" do
    body = <<-JSON
    {
      "error": {
        "code": "invalid_input",
        "message": "unsupported location for server type"
      }
    }
    JSON
    Hetzner::Instance::Create.invalid_input?(body).should be_true
  end

  it "ignores the code when it only appears inside a message" do
    body = %({"error":{"code":"resource_unavailable","message":"invalid_input is not the error here"}})
    Hetzner::Instance::Create.invalid_input?(body).should be_false
  end

  it "keeps retrying on other error codes" do
    body = %({"error":{"code":"resource_unavailable","message":"no capacity available"}})
    Hetzner::Instance::Create.invalid_input?(body).should be_false
  end

  it "treats a body that is not JSON as retryable" do
    Hetzner::Instance::Create.invalid_input?("bad gateway").should be_false
    Hetzner::Instance::Create.invalid_input?("").should be_false
  end
end
