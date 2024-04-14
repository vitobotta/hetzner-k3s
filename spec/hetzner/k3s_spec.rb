# frozen_string_literal: true

RSpec.describe Hetzner::K3s do
  it "has a version number" do
    expect(Hetzner::K3s::VERSION).not_to be_nil
  end
end
