# frozen_string_literal: true

RSpec.describe "Admin UI", type: :request do
  it "renders the admin HTML page" do
    get "/admin", {}, {"HTTP_ACCEPT" => "text/html"}
    expect(last_response.status).to eq(200)
    expect(last_response.headers["Content-Type"]).to include("text/html")
    expect(last_response.body).to include("Gem::Server Admin")
  end
end

