# frozen_string_literal: true

require_relative "stats_tracking"

module Philiprehberger
  module RateLimiter
    class TokenBucket
      include StatsTracking

      attr_reader :rate, :capacity

      def initialize(rate:, capacity:)
        @rate = rate.to_f
        @capacity = capacity.to_f
        @store = {}
        @mutex = Mutex.new
        init_stats
      end

      def allow?(key, weight: 1)
        @mutex.synchronize { try_acquire(key, weight.to_f) }
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

      def info(key)
        @mutex.synchronize { build_info(key) }
      end

      def refund(key, amount: 1)
        @mutex.synchronize { refund_tokens(key, amount.to_f) }
      end

      private

      def try_acquire(key, weight)
        refill(key)
        bucket = fetch_bucket(key)
        return reject_request(key) if bucket[:tokens] < weight

        bucket[:tokens] -= weight
        record_allowed(key)
        true
      end

      def reject_request(key)
        record_rejected(key)
        false
      end

      def build_info(key)
        tokens = token_count(key)
        deficit = @capacity - tokens
        reset_at = deficit.positive? ? now + (deficit / @rate) : nil
        {
          remaining: tokens.to_i,
          reset_at: reset_at,
          capacity: @capacity.to_i,
          rate: @rate,
          tokens: tokens
        }
      end

      def refund_tokens(key, amount)
        refill(key)
        bucket = fetch_bucket(key)
        bucket[:tokens] = [bucket[:tokens] + amount, @capacity].min
        nil
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
