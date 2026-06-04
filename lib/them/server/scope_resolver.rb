# frozen_string_literal: true

require_relative "../../../config/database"

module Them
  module Server
    class ScopeResolver
      attr_reader :path_parts, :include_gem_name

      def initialize(path_parts, include_gem_name: true)
        @path_parts = Array(path_parts).compact
        @include_gem_name = include_gem_name
      end

      def gem_name
        @gem_name ||= path_parts.last if include_gem_name && !path_parts.empty?
      end

      def scope_path
        @scope_path ||= if include_gem_name
          path_parts[0..-2] || []
        else
          path_parts
        end
      end

      def scope(create: true)
        return if scope_path.empty?

        db = Database.db
        current_scope = nil

        scope_path.each do |name|
          parent_id = current_scope ? current_scope[:id] : nil
          existing_scope = db[:scopes].where(name: name, parent_id: parent_id).first

          if existing_scope
            current_scope = existing_scope
          elsif create
            # Create scope if it doesn't exist
            new_id = db[:scopes].insert(
              name: name,
              parent_id: parent_id,
              created_at: Time.now,
              updated_at: Time.now
            )
            current_scope = db[:scopes].where(id: new_id).first
          else
            # Scope doesn't exist and we're not creating it
            return nil
          end
        end

        current_scope
      end

      def root_scope?
        scope_path.empty?
      end
    end
  end
end
