# frozen_string_literal: true

require_relative "rate_limiter/version"
require_relative "rate_limiter/sliding_window"
require_relative "rate_limiter/token_bucket"

module Philiprehberger
  module RateLimiter
    class Error < StandardError; end

    def self.sliding_window(limit:, window:)
      SlidingWindow.new(limit: limit, window: window)
    end

    def self.token_bucket(rate:, capacity:)
      TokenBucket.new(rate: rate, capacity: capacity)
    end
  end
end
