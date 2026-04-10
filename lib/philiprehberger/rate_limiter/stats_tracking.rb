# frozen_string_literal: true

module Philiprehberger
  module RateLimiter
    module StatsTracking
      def stats(key)
        @mutex.synchronize { fetch_stats(key).dup }
      end

      def on_reject(&block)
        @mutex.synchronize { @on_reject_callback = block }
        self
      end

      # Execute a block if allowed, returning the result in a hash.
      #
      # @param key [Symbol, String] the rate limit key
      # @param weight [Integer] tokens to consume
      # @yield the block to execute when allowed
      # @return [Hash] { allowed: true, value: result } or { allowed: false, value: nil }
      def throttle(key, weight: 1, &block)
        if allow?(key, weight: weight)
          { allowed: true, value: block.call }
        else
          { allowed: false, value: nil }
        end
      end

      # Like allow? but raises RateLimitExceeded when rejected.
      #
      # @param key [Symbol, String] the rate limit key
      # @param weight [Integer] tokens to consume
      # @return [true]
      # @raise [RateLimitExceeded] if the rate limit is exceeded
      def allow!(key, weight: 1)
        return true if allow?(key, weight: weight)

        raise RateLimitExceeded, key
      end

      # Return all currently tracked keys.
      #
      # @return [Array<String>]
      def keys
        @mutex.synchronize { @store.keys }
      end

      private

      def fetch_stats(key)
        @stats_store[key.to_s] ||= { allowed: 0, rejected: 0 }
      end

      def record_allowed(key)
        fetch_stats(key)[:allowed] += 1
      end

      def record_rejected(key)
        fetch_stats(key)[:rejected] += 1
        fire_on_reject(key)
      end

      def fire_on_reject(key)
        @on_reject_callback&.call(key)
      end

      def init_stats
        @stats_store = {}
        @on_reject_callback = nil
      end
    end
  end
end
