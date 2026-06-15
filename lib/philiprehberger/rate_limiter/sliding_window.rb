# frozen_string_literal: true

require_relative 'stats_tracking'

module Philiprehberger
  module RateLimiter
    class SlidingWindow
      include StatsTracking

      attr_reader :limit, :window

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

      # Number of currently consumed slots for a key (after expiring old entries).
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Integer] count of active entries in the window
      def used(key)
        @mutex.synchronize do
          cleanup(key)
          fetch_entries(key).length
        end
      end

      # Clear the window for a key, discarding all tracked entries.
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
      # Mirrors {#allow_batch} for inspection rather than acquisition.
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
        @mutex.synchronize { refund_entries(key, amount) }
      end

      # Forcefully consume all remaining capacity for a key.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Integer] the number of slots drained
      def drain(key = :default)
        @mutex.synchronize { drain_entries(key) }
      end

      # Seconds until the next request would be allowed
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Float] seconds to wait (0 if allowed now)
      def wait_time(key = :default)
        @mutex.synchronize do
          cleanup(key)
          entries = fetch_entries(key)
          return 0.0 if entries.length < @limit

          oldest = entries.min
          return 0.0 if oldest.nil?

          wait = oldest + @window - now
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
          cleanup(key)
          entries = fetch_entries(key)
          return 0.0 if entries.length < @limit

          oldest = entries.min
          return 0.0 if oldest.nil?

          wait = (oldest + @window) - now
          [wait, 0.0].max
        end
      end

      # Time when the current window expires
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Time, nil] absolute time when window resets, nil if no requests
      def window_reset_at(key = :default)
        @mutex.synchronize do
          entries = fetch_entries(key)
          return nil if entries.empty?

          cleanup(key)
          entries = fetch_entries(key)
          return nil if entries.empty?

          oldest = entries.min
          elapsed = now - oldest
          Time.now + (@window - elapsed)
        end
      end

      private

      def try_acquire(key, weight)
        cleanup(key)
        entries = fetch_entries(key)
        return reject_request(key) if entries.length + weight > @limit

        weight.times { entries << now }
        record_allowed(key)
        true
      end

      def reject_request(key)
        record_rejected(key)
        false
      end

      def build_info(key)
        cleanup(key)
        entries = fetch_entries(key)
        oldest = entries.min
        {
          remaining: [@limit - entries.length, 0].max,
          reset_at: oldest ? oldest + @window : nil,
          limit: @limit,
          window: @window,
          used: entries.length
        }
      end

      def refund_entries(key, amount)
        entries = fetch_entries(key)
        [amount, entries.length].min.times { entries.pop }
        nil
      end

      def drain_entries(key)
        cleanup(key)
        entries = fetch_entries(key)
        remaining = [@limit - entries.length, 0].max
        remaining.times { entries << now }
        remaining
      end

      def count_remaining(key)
        cleanup(key)
        [@limit - fetch_entries(key).length, 0].max
      end

      def cleanup(key)
        entries = fetch_entries(key)
        cutoff = now - @window
        entries.reject! { |ts| ts <= cutoff }
      end

      def fetch_entries(key)
        @store[key.to_s] ||= []
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
