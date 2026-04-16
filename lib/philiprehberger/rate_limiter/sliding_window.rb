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

      def allow?(key, weight: 1)
        @mutex.synchronize { try_acquire(key, weight) }
      end

      def peek(key)
        @mutex.synchronize { count_remaining(key).positive? }
      end

      def remaining(key)
        @mutex.synchronize { count_remaining(key) }
      end

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

      def info(key)
        @mutex.synchronize { build_info(key) }
      end

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
