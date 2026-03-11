# frozen_string_literal: true

module Philiprehberger
  module RateLimiter
    class TokenBucket
      def initialize(rate:, capacity:)
        @rate = rate.to_f
        @capacity = capacity.to_f
        @store = {}
        @mutex = Mutex.new
      end

      def allow?(key)
        @mutex.synchronize { try_acquire(key) }
      end

      def peek(key)
        @mutex.synchronize { token_count(key) >= 1.0 }
      end

      def remaining(key)
        @mutex.synchronize { token_count(key).to_i }
      end

      def reset(key)
        @mutex.synchronize { @store.delete(key.to_s) }
      end

      private

      def try_acquire(key)
        refill(key)
        bucket = fetch_bucket(key)
        return false if bucket[:tokens] < 1.0

        bucket[:tokens] -= 1.0
        true
      end

      def token_count(key)
        refill(key)
        bucket = fetch_bucket(key)
        [bucket[:tokens], @capacity].min
      end

      def refill(key)
        bucket = fetch_bucket(key)
        elapsed = now - bucket[:last_refill]
        bucket[:tokens] = [bucket[:tokens] + (elapsed * @rate), @capacity].min
        bucket[:last_refill] = now
      end

      def fetch_bucket(key)
        @store[key.to_s] ||= { tokens: @capacity, last_refill: now }
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
