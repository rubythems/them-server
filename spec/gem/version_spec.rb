# frozen_string_literal: true

RSpec.describe Gem::Server::Version do
  it_behaves_like "a Version module", described_class

  it "is greater than 0.1.0" do
    expect(Gem::Version.new(described_class) >= Gem::Version.new("0.1.0")).to(be(true))
  end
end
