# frozen_string_literal: true

module Philiprehberger
  module RateLimiter
    # A limiter that always allows requests. Useful for tests and feature-flagged rollouts.
    class Noop
      def allow?(_key = :default, weight: 1)
        _ = weight
        true
      end

      def allow_batch(keys)
        keys.to_h { |key| [key, true] }
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

      def used(_key = :default)
        0
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

      # Return previously consumed slot(s). No-op always has capacity, so this
      # does nothing and mirrors the real limiters' signature.
      #
      # @return [nil]
      def refund(_key = :default, amount: 1)
        _ = amount
        nil
      end

      # Seconds until the next request would be allowed. Always allowed.
      #
      # @return [Float] always 0.0
      def wait_time(_key = :default, weight: 1)
        _ = weight
        0.0
      end

      # Time when the current window expires. Noop has no window.
      #
      # @return [nil]
      def window_reset_at(_key = :default)
        nil
      end

      # Blocking acquire. Noop always has capacity, so it returns immediately.
      #
      # @return [true]
      def block(_key = :default, timeout: nil, weight: 1)
        _ = timeout
        _ = weight
        true
      end

      def clear
        nil
      end

      def info(_key = :default)
        { remaining: Float::INFINITY, limit: Float::INFINITY, used: 0 }
      end

      def info_batch(keys)
        keys.to_h { |key| [key, info(key)] }
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

      # Register a callback for rejected requests.
      #
      # Noop ignores the callback since nothing is ever rejected.
      #
      # @return [self]
      def on_reject(&block)
        _ = block
        self
      end
    end
  end
end
