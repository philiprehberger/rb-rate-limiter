# frozen_string_literal: true

module Philiprehberger
  module RateLimiter
    # A limiter that always allows requests. Useful for tests and feature-flagged rollouts.
    class Noop
      def allow?(_key = :default, weight: 1)
        _ = weight
        true
      end

      def allow!(_key = :default, weight: 1)
        _ = weight
        true
      end

      def peek(_key = :default)
        true
      end

      def remaining(_key = :default)
        Float::INFINITY
      end

      def reset(_key = :default)
        nil
      end

      def drain(_key = :default)
        Float::INFINITY
      end

      def retry_after(_key = :default)
        0.0
      end

      def clear
        nil
      end

      def info(_key = :default)
        { remaining: Float::INFINITY, limit: Float::INFINITY, used: 0 }
      end

      def stats(_key = :default)
        { allowed: 0, rejected: 0 }
      end

      def keys
        []
      end

      def throttle(_key = :default, weight: 1, &block)
        _ = weight
        { allowed: true, value: block.call }
      end

      def on_reject(&)
        self
      end
    end
  end
end
