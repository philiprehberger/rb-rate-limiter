# frozen_string_literal: true

require_relative 'stats_tracking'

module Philiprehberger
  module RateLimiter
    # Fixed-window rate limiter. Each key stores a single counter plus the
    # timestamp when its current window opened — O(1) memory per key. The
    # counter resets to zero once the window duration elapses.
    class FixedWindow
      include StatsTracking

      attr_reader :limit, :window

      # @param limit [Integer] max requests allowed per window
      # @param window [Numeric] window duration in seconds
      def initialize(limit:, window:)
        @limit = limit
        @window = window
        @store = {}
        @mutex = Mutex.new
        init_stats
      end

      # Check if a request is allowed and consume slot(s) in the window.
      #
      # @param key [Symbol, String] the rate limit key
      # @param weight [Integer] number of slots to consume (default 1)
      # @return [Boolean] true if the request was allowed, false if rejected
      def allow?(key, weight: 1)
        @mutex.synchronize { try_acquire(key, weight) }
      end

      # Check many keys in a single mutex acquisition.
      #
      # @param keys [Array<Symbol, String>] the keys to check and consume
      # @return [Hash{Object => Boolean}] mapping of each key to the allow result
      def allow_batch(keys)
        @mutex.synchronize do
          keys.to_h { |key| [key, try_acquire(key, 1)] }
        end
      end

      # Check if a request would be allowed without consuming a slot.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Boolean] true if capacity is available, false otherwise
      def peek(key)
        @mutex.synchronize { count_remaining(key).positive? }
      end

      # Return the number of remaining slots in the current window.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Integer] count of remaining capacity (0 if at or over limit)
      def remaining(key)
        @mutex.synchronize { count_remaining(key) }
      end

      # Number of currently consumed slots for a key in the active window.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Integer] count consumed in the current window
      def used(key)
        @mutex.synchronize { roll(key)[:count] }
      end

      # Clear the window for a key.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [void]
      def reset(key)
        @mutex.synchronize { @store.delete(key.to_s) }
      end

      # Clear state for all keys (resets quotas and stats for every tracked key)
      #
      # @return [void]
      def clear
        @mutex.synchronize do
          @store.clear
          @stats_store.clear
        end
        nil
      end

      # Build a usage info hash for a key.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Hash] keys :remaining, :reset_at, :limit, :window, :used
      def info(key)
        @mutex.synchronize { build_info(key) }
      end

      # Build info hashes for many keys in a single mutex acquisition.
      #
      # @param keys [Array<Symbol, String>] the keys to inspect
      # @return [Hash{Object => Hash}] mapping of each key to its info hash
      def info_batch(keys)
        @mutex.synchronize do
          keys.to_h { |key| [key, build_info(key)] }
        end
      end

      # Return previously consumed slot(s) to a key (e.g. on downstream failure).
      #
      # @param key [Symbol, String] the rate limit key
      # @param amount [Integer] number of slots to refund (default 1)
      # @return [nil]
      def refund(key, amount: 1)
        @mutex.synchronize do
          bucket = roll(key)
          bucket[:count] = [bucket[:count] - amount, 0].max
          nil
        end
      end

      # Seconds until the next request would be allowed.
      #
      # @param key [Symbol, String] the rate limit key
      # @param weight [Integer] slots needed
      # @return [Float] seconds to wait (0 if allowed now)
      def wait_time(key = :default, weight: 1)
        @mutex.synchronize do
          bucket = roll(key)
          return 0.0 if bucket[:count] + weight <= @limit

          wait = (bucket[:window_start] + @window) - now
          [wait, 0.0].max
        end
      end

      # Seconds until the next request would be allowed, suitable for the HTTP
      # Retry-After header. Returns 0.0 when a request is allowed right now.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Float] seconds until next allowed request (0.0 if allowed now)
      def retry_after(key = :default)
        @mutex.synchronize do
          bucket = roll(key)
          return 0.0 if bucket[:count] < @limit

          wait = (bucket[:window_start] + @window) - now
          [wait, 0.0].max
        end
      end

      private

      def try_acquire(key, weight)
        bucket = roll(key)
        if bucket[:count] + weight > @limit
          record_rejected(key)
          return false
        end

        bucket[:count] += weight
        record_allowed(key)
        true
      end

      def build_info(key)
        bucket = roll(key)
        used = bucket[:count]
        {
          remaining: [@limit - used, 0].max,
          reset_at: used.positive? ? bucket[:window_start] + @window : nil,
          limit: @limit,
          window: @window,
          used: used
        }
      end

      def count_remaining(key)
        [@limit - roll(key)[:count], 0].max
      end

      # Fetch the bucket for a key, rolling it into a fresh window when the
      # current window has elapsed.
      def roll(key)
        bucket = fetch_bucket(key)
        if now - bucket[:window_start] >= @window
          bucket[:count] = 0
          bucket[:window_start] = now
        end
        bucket
      end

      def fetch_bucket(key)
        @store[key.to_s] ||= { count: 0, window_start: now }
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
