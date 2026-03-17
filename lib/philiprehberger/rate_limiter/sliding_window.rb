# frozen_string_literal: true

require_relative "stats_tracking"

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

      def info(key)
        @mutex.synchronize { build_info(key) }
      end

      def refund(key, amount: 1)
        @mutex.synchronize { refund_entries(key, amount) }
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
