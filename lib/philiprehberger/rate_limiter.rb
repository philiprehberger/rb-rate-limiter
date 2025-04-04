# frozen_string_literal: true

require_relative 'rate_limiter/version'
require_relative 'rate_limiter/stats_tracking'
require_relative 'rate_limiter/sliding_window'
require_relative 'rate_limiter/token_bucket'
require_relative 'rate_limiter/noop'

module Philiprehberger
  module RateLimiter
    class Error < StandardError; end

    # Raised by allow! when the rate limit is exceeded
    class RateLimitExceeded < Error
      # @return [String] the key that was rate-limited
      attr_reader :key

      def initialize(key)
        @key = key
        super("Rate limit exceeded for #{key}")
      end
    end

    def self.sliding_window(limit:, window:)
      SlidingWindow.new(limit: limit, window: window)
    end

    def self.token_bucket(rate:, capacity:)
      TokenBucket.new(rate: rate, capacity: capacity)
    end

    # Build a no-op limiter that always allows requests.
    #
    # @return [Noop]
    def self.noop
      Noop.new
    end
  end
end
