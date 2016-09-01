module Restruct
  module Types
    # Base class for all objects a factory can produce
    class Base
      include Restruct::Utils::Inspectable
      extend Forwardable

      def_delegators :@factory, :connection, :connection

      # @return [String] The key used to identify the struct on redis
      attr_reader :key

      def initialize(key:, factory:)
        @factory = factory
        @key = key
      end

      def with
        self.connection.pool.with do |c|
          begin
            Thread.current[:__restruct_connection] = c
            yield(c)
          ensure
            Thread.current[:__restruct_connection] = nil
          end
        end
      end

      def to_h
        return { key: @key }
      end

      def create
        return unless block_given?
        subfactory = @factory.factory(@key)
        yield(subfactory)
      end
      protected :create

      # :nocov:
      def inspectable_attributes
        { key: @key, factory: @factory }
      end
      # :nocov:
    end
  end
end
