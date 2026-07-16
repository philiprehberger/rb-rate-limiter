# frozen_string_literal: true

require_relative 'stats_tracking'

module Philiprehberger
  module RateLimiter
    class TokenBucket
      include StatsTracking

      attr_reader :rate, :capacity

      # @param rate [Numeric] tokens refilled per second
      # @param capacity [Numeric] max tokens the bucket can hold
      # @param max_keys [Integer, nil] cap on tracked keys; least-recently-touched
      #   key is evicted (LRU) once the cap is exceeded. nil means unbounded.
      def initialize(rate:, capacity:, max_keys: nil)
        @rate = rate.to_f
        @capacity = capacity.to_f
        @max_keys = max_keys
        @store = {}
        @mutex = Mutex.new
        init_stats
      end

      def allow?(key, weight: 1)
        @mutex.synchronize { try_acquire(key, weight.to_f) }
      end

      # Check many keys in a single mutex acquisition.
      #
      # @param keys [Array<Symbol, String>] the keys to check and consume
      # @return [Hash{Object => Boolean}] mapping of each key to the allow result
      def allow_batch(keys)
        @mutex.synchronize do
          keys.to_h { |key| [key, try_acquire(key, 1.0)] }
        end
      end

      def peek(key)
        @mutex.synchronize { token_count(key) >= 1.0 }
      end

      def remaining(key)
        @mutex.synchronize { token_count(key).to_i }
      end

      # Number of currently consumed tokens for a key.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Integer] capacity minus remaining tokens
      def used(key)
        @mutex.synchronize { @capacity.to_i - token_count(key).to_i }
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

      def refund(key, amount: 1)
        @mutex.synchronize { refund_tokens(key, amount.to_f) }
      end

      # Drop keys whose bucket has fully refilled back to capacity, reclaiming
      # memory for idle keys. Also clears their stats.
      #
      # @return [Integer] the number of keys pruned
      def prune
        @mutex.synchronize do
          pruned = 0
          tracked = @store.keys
          tracked.each do |key|
            refill(key)
            next unless @store[key][:tokens] >= @capacity

            @store.delete(key)
            @stats_store.delete(key)
            pruned += 1
          end
          pruned
        end
      end

      # Forcefully consume all remaining tokens for a key.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Integer] the integer floor of tokens drained
      def drain(key = :default)
        @mutex.synchronize { drain_tokens(key) }
      end

      # Seconds until the next request would be allowed
      #
      # @param key [Symbol, String] the rate limit key
      # @param weight [Integer] tokens needed
      # @return [Float] seconds to wait (0 if allowed now)
      def wait_time(key = :default, weight: 1)
        @mutex.synchronize do
          refill(key)
          tokens = @store[key.to_s] ? @store[key.to_s][:tokens] : @capacity
          return 0.0 if tokens >= weight

          needed = weight - tokens
          needed / @rate
        end
      end

      # Seconds until the next request would be allowed, suitable for the HTTP
      # Retry-After header. Returns 0.0 when a token is available right now.
      #
      # @param key [Symbol, String] the rate limit key
      # @return [Float] seconds until 1 token is available (0.0 if allowed now)
      def retry_after(key = :default)
        @mutex.synchronize do
          refill(key)
          bucket = @store[key.to_s]
          tokens = bucket ? bucket[:tokens] : @capacity
          return 0.0 if tokens >= 1.0

          needed = 1.0 - tokens
          needed / @rate
        end
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

      def drain_tokens(key)
        refill(key)
        bucket = fetch_bucket(key)
        drained = [bucket[:tokens], 0.0].max.floor
        bucket[:tokens] = 0.0
        drained
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
        k = key.to_s
        bucket = @store[k]
        if bucket
          @store.delete(k)
          @store[k] = bucket
        else
          bucket = @store[k] = { tokens: @capacity, last_refill: now }
          evict_lru
        end
        bucket
      end

      def evict_lru
        return unless @max_keys

        while @store.size > @max_keys
          oldest = @store.keys.first
          @store.delete(oldest)
          @stats_store.delete(oldest)
        end
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
