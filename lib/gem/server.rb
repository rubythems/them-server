# frozen_string_literal: true

# third party gems
require "version_gem"

# includes gem files
require_relative "server/version"

module Gem
  module Server
    class Error < StandardError; end
    # Your code goes here...
  end
end

# Extend Gem::Server with VersionGem helpers to provide semantic version helpers.
Gem::Server::Version.class_eval do
  extend VersionGem::Basic
end
