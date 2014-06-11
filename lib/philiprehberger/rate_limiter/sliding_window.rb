# frozen_string_literal: true

module Philiprehberger
  module RateLimiter
    class SlidingWindow
      def initialize(limit:, window:)
        @limit = limit
        @window = window
        @store = {}
        @mutex = Mutex.new
      end

      def allow?(key)
        @mutex.synchronize { try_acquire(key) }
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

      private

      def try_acquire(key)
        cleanup(key)
        entries = fetch_entries(key)
        return false if entries.length >= @limit

        entries << now
        true
      end

      def count_remaining(key)
        cleanup(key)
        entries = fetch_entries(key)
        [@limit - entries.length, 0].max
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
