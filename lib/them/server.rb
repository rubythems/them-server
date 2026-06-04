# frozen_string_literal: true

require "version_gem"
require_relative "server/version"

module Them
  module Server
  end
end

Them::Server::Version.class_eval do
  extend VersionGem::Basic
end
