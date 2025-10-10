# frozen_string_literal: true

RSpec.describe "Root", type: :request do
  it "lists gems in root scope" do
    get "/"

    # Root path should return list of gems in null/root scope
    expect(last_response.status).to eq(200)
  end
end
