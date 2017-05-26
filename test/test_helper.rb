# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'securerandom'
require 'bundler/setup'
require 'minitest/autorun'
require 'flexmock/minitest'

ci_build = ENV['CI_BUILD'].to_i.positive?

bundler_groups = %i[default test]
bundler_groups << (ci_build ? :ci : :debug)
Bundler.require(*bundler_groups)

# Start coverage
Codacy::Reporter.start if ci_build

# Default Redstruct config
require 'redstruct/all'
Redstruct.config.default_namespace = "redstruct:test:#{SecureRandom.uuid}"
Redstruct.config.default_connection = ConnectionPool.new(size: 5, timeout: 2) do
  Redis.new(host: ENV.fetch('REDIS_HOST', '127.0.0.1'), port: ENV.fetch('REDIS_PORT', 6379).to_i, db: ENV.fetch('REDIS_DB', 0).to_i)
end

# Setup cleanup hook
Minitest.after_run do
  Redstruct.config.default_connection.with do |conn|
    conn.flushdb
    conn.script(:flush)
  end
end

# Small class used to generate thread-safe sequence when creating per-test
# factories
class AtomicInteger
  def initialize
    @lock = Mutex.new
    @current = 0
  end

  def incr
    value = nil
    @lock.synchronize do
      value = @current
      @current += 1
    end

    return value
  end
end

module Redstruct
  # Base class for all Redstruct tests. Configures the gem, provides a default factory, and makes sure to clean it up
  # at the end
  class Test < Minitest::Test
    @@counter = AtomicInteger.new # rubocop: disable Style/ClassVars

    parallelize_me!
    make_my_diffs_pretty!

    # Use this helper to create a factory that the test class will keep track of and remove at the end
    def create_factory(namespace = nil)
      namespace ||= "#{Redstruct.config.default_namespace}:#{@@counter.incr}"
      return Redstruct::Factory.new(namespace: namespace)
    end

    # Helper when trying to ensure a particular redis-rb command was called
    # while still calling it. This allows for testing things outside of our
    # control (e.g. srandmember returning random items)
    # The reason we don't simply just mock the return value is to ensure
    # that tests will break if a command (e.g. srandmember) changes its return
    # value
    def ensure_command_called(object, command, *args, allow: true)
      mock = flexmock(object.connection).should_receive(command).with(object.key, *args)
      mock = mock.pass_thru if allow

      return mock
    end
  end
end
