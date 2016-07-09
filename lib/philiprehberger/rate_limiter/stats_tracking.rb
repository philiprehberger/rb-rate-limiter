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
