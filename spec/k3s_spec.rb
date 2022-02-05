# frozen_string_literal: true

RSpec.describe K3s do
  it 'has a version number' do
    expect(K3s::VERSION).not_to be nil
  end

  it 'does something useful' do
    expect(false).to eq(true)
  end
end
