# frozen_string_literal: true

require "rake"

RSpec.describe "Rake tasks" do
  before :all do
    Rake.application = Rake::Application.new
    load File.expand_path("../../Rakefile", __dir__)
  end

  it "defines db tasks" do
    expect(Rake::Task.task_defined?("db:migrate")).to be(true)
    expect(Rake::Task.task_defined?("db:version")).to be(true)
    expect(Rake::Task.task_defined?("db:rollback")).to be(true)
    expect(Rake::Task.task_defined?("db:seed")).to be(true)
    expect(Rake::Task.task_defined?("db:reset")).to be(true)
  end

  it "defines federation tasks" do
    expect(Rake::Task.task_defined?("federation:list_known")).to be(true)
    expect(Rake::Task.task_defined?("federation:seed_known")).to be(true)
    expect(Rake::Task.task_defined?("federation:announce")).to be(true)
    expect(Rake::Task.task_defined?("federation:subscribe")).to be(true)
  end

  it "invokes db:version without error" do
    expect { Rake::Task["db:version"].invoke }.not_to raise_error
  end
end
