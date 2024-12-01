# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::RateLimiter do
  it 'has a version number' do
    expect(described_class::VERSION).not_to be_nil
  end

  describe '.sliding_window' do
    it 'returns a SlidingWindow instance' do
      limiter = described_class.sliding_window(limit: 5, window: 60)
      expect(limiter).to be_a(described_class::SlidingWindow)
    end
  end

  describe '.token_bucket' do
    it 'returns a TokenBucket instance' do
      limiter = described_class.token_bucket(rate: 1, capacity: 5)
      expect(limiter).to be_a(described_class::TokenBucket)
    end
  end
end

RSpec.describe Philiprehberger::RateLimiter::SlidingWindow do
  subject(:limiter) { described_class.new(limit: 3, window: 1) }

  describe '#allow?' do
    it 'allows requests within the limit' do
      3.times { expect(limiter.allow?('user1')).to be true }
    end

    it 'blocks requests over the limit' do
      3.times { limiter.allow?('user1') }
      expect(limiter.allow?('user1')).to be false
    end

    it 'tracks keys independently' do
      3.times { limiter.allow?('user1') }
      expect(limiter.allow?('user2')).to be true
    end

    it 'resets after the window expires' do
      3.times { limiter.allow?('user1') }
      sleep(1.1)
      expect(limiter.allow?('user1')).to be true
    end
  end

  describe '#allow? with weight' do
    it 'consumes multiple tokens with weight' do
      expect(limiter.allow?('user1', weight: 2)).to be true
      expect(limiter.remaining('user1')).to eq(1)
    end

    it 'rejects when weight exceeds remaining' do
      limiter.allow?('user1', weight: 2)
      expect(limiter.allow?('user1', weight: 2)).to be false
    end

    it 'allows exact remaining weight' do
      limiter.allow?('user1', weight: 2)
      expect(limiter.allow?('user1', weight: 1)).to be true
    end

    it 'rejects when weight exceeds total limit' do
      expect(limiter.allow?('user1', weight: 4)).to be false
    end

    it 'defaults weight to 1' do
      limiter.allow?('user1')
      expect(limiter.remaining('user1')).to eq(2)
    end
  end

  describe '#peek' do
    it 'returns true when requests are available' do
      expect(limiter.peek('user1')).to be true
    end

    it 'returns false when limit is reached' do
      3.times { limiter.allow?('user1') }
      expect(limiter.peek('user1')).to be false
    end

    it 'does not consume a request' do
      limiter.peek('user1')
      expect(limiter.remaining('user1')).to eq(3)
    end
  end

  describe '#remaining' do
    it 'returns the full limit initially' do
      expect(limiter.remaining('user1')).to eq(3)
    end

    it 'decreases after each allowed request' do
      2.times { limiter.allow?('user1') }
      expect(limiter.remaining('user1')).to eq(1)
    end
  end

  describe '#reset' do
    it 'clears state for a key' do
      3.times { limiter.allow?('user1') }
      limiter.reset('user1')
      expect(limiter.remaining('user1')).to eq(3)
    end
  end

  describe '#limit' do
    it 'returns the configured limit' do
      expect(limiter.limit).to eq(3)
    end
  end

  describe '#window' do
    it 'returns the configured window' do
      expect(limiter.window).to eq(1)
    end
  end

  describe '#info' do
    it 'returns usage info for a key' do
      2.times { limiter.allow?('user1') }
      info = limiter.info('user1')
      expect(info[:remaining]).to eq(1)
      expect(info[:limit]).to eq(3)
      expect(info[:window]).to eq(1)
      expect(info[:used]).to eq(2)
    end

    it 'returns full limit for unknown key' do
      info = limiter.info('new_key')
      expect(info[:remaining]).to eq(3)
      expect(info[:used]).to eq(0)
    end

    it 'includes reset_at timestamp when entries exist' do
      limiter.allow?('user1')
      info = limiter.info('user1')
      expect(info[:reset_at]).to be_a(Float)
    end

    it 'returns nil reset_at for unused key' do
      info = limiter.info('new_key')
      expect(info[:reset_at]).to be_nil
    end
  end

  describe '#stats' do
    it 'returns zeroes for an unused key' do
      stats = limiter.stats('user1')
      expect(stats).to eq({ allowed: 0, rejected: 0 })
    end

    it 'counts allowed requests' do
      2.times { limiter.allow?('user1') }
      stats = limiter.stats('user1')
      expect(stats[:allowed]).to eq(2)
    end

    it 'counts rejected requests' do
      3.times { limiter.allow?('user1') }
      2.times { limiter.allow?('user1') }
      stats = limiter.stats('user1')
      expect(stats[:rejected]).to eq(2)
    end

    it 'tracks keys independently' do
      3.times { limiter.allow?('user1') }
      limiter.allow?('user1')
      limiter.allow?('user2')
      expect(limiter.stats('user1')[:rejected]).to eq(1)
      expect(limiter.stats('user2')[:allowed]).to eq(1)
    end

    it 'returns a copy so external mutation is safe' do
      limiter.allow?('user1')
      stats = limiter.stats('user1')
      stats[:allowed] = 999
      expect(limiter.stats('user1')[:allowed]).to eq(1)
    end
  end

  describe '#refund' do
    it 'restores capacity after a refund' do
      3.times { limiter.allow?('user1') }
      expect(limiter.remaining('user1')).to eq(0)
      limiter.refund('user1', amount: 1)
      expect(limiter.remaining('user1')).to eq(1)
    end

    it 'does not refund more than consumed' do
      limiter.allow?('user1')
      limiter.refund('user1', amount: 5)
      expect(limiter.remaining('user1')).to eq(3)
    end

    it 'defaults amount to 1' do
      2.times { limiter.allow?('user1') }
      limiter.refund('user1')
      expect(limiter.remaining('user1')).to eq(2)
    end

    it 'returns nil' do
      limiter.allow?('user1')
      expect(limiter.refund('user1')).to be_nil
    end
  end

  describe '#on_reject' do
    it 'fires callback when a request is rejected' do
      rejected_keys = []
      limiter.on_reject { |key| rejected_keys << key }
      3.times { limiter.allow?('user1') }
      limiter.allow?('user1')
      expect(rejected_keys).to eq(['user1'])
    end

    it 'does not fire on allowed requests' do
      called = false
      limiter.on_reject { |_key| called = true }
      limiter.allow?('user1')
      expect(called).to be false
    end

    it 'fires for each rejection' do
      count = 0
      limiter.on_reject { |_key| count += 1 }
      3.times { limiter.allow?('user1') }
      3.times { limiter.allow?('user1') }
      expect(count).to eq(3)
    end

    it 'returns self for chaining' do
      result = limiter.on_reject { |_key| nil }
      expect(result).to be(limiter)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent access without errors' do
      window_limiter = described_class.new(limit: 100, window: 10)
      threads = Array.new(10) do
        Thread.new { 20.times { window_limiter.allow?('shared') } }
      end
      threads.each(&:join)
      expect(window_limiter.remaining('shared')).to be >= 0
    end
  end
end

RSpec.describe Philiprehberger::RateLimiter::TokenBucket do
  subject(:limiter) { described_class.new(rate: 10, capacity: 3) }

  describe '#allow?' do
    it 'allows requests within capacity' do
      3.times { expect(limiter.allow?('user1')).to be true }
    end

    it 'blocks when tokens are exhausted' do
      3.times { limiter.allow?('user1') }
      expect(limiter.allow?('user1')).to be false
    end

    it 'tracks keys independently' do
      3.times { limiter.allow?('user1') }
      expect(limiter.allow?('user2')).to be true
    end

    it 'refills tokens over time' do
      3.times { limiter.allow?('user1') }
      sleep(0.2)
      expect(limiter.allow?('user1')).to be true
    end
  end

  describe '#allow? with weight' do
    it 'consumes multiple tokens with weight' do
      expect(limiter.allow?('user1', weight: 2)).to be true
      expect(limiter.remaining('user1')).to eq(1)
    end

    it 'rejects when weight exceeds remaining tokens' do
      limiter.allow?('user1', weight: 2)
      expect(limiter.allow?('user1', weight: 2)).to be false
    end

    it 'allows exact remaining weight' do
      limiter.allow?('user1', weight: 2)
      expect(limiter.allow?('user1', weight: 1)).to be true
    end

    it 'rejects when weight exceeds total capacity' do
      expect(limiter.allow?('user1', weight: 4)).to be false
    end

    it 'defaults weight to 1' do
      limiter.allow?('user1')
      expect(limiter.remaining('user1')).to eq(2)
    end
  end

  describe '#peek' do
    it 'returns true when tokens are available' do
      expect(limiter.peek('user1')).to be true
    end

    it 'returns false when tokens are exhausted' do
      3.times { limiter.allow?('user1') }
      expect(limiter.peek('user1')).to be false
    end

    it 'does not consume a token' do
      limiter.peek('user1')
      expect(limiter.remaining('user1')).to eq(3)
    end
  end

  describe '#remaining' do
    it 'returns the full capacity initially' do
      expect(limiter.remaining('user1')).to eq(3)
    end

    it 'decreases after consumption' do
      2.times { limiter.allow?('user1') }
      expect(limiter.remaining('user1')).to eq(1)
    end
  end

  describe '#reset' do
    it 'clears state for a key' do
      3.times { limiter.allow?('user1') }
      limiter.reset('user1')
      expect(limiter.remaining('user1')).to eq(3)
    end
  end

  describe '#rate' do
    it 'returns the configured rate' do
      expect(limiter.rate).to eq(10.0)
    end
  end

  describe '#capacity' do
    it 'returns the configured capacity' do
      expect(limiter.capacity).to eq(3.0)
    end
  end

  describe '#info' do
    it 'returns usage info for a key' do
      2.times { limiter.allow?('user1') }
      info = limiter.info('user1')
      expect(info[:remaining]).to eq(1)
      expect(info[:capacity]).to eq(3)
      expect(info[:rate]).to eq(10.0)
      expect(info[:tokens]).to be_a(Float)
    end

    it 'returns full capacity for unknown key' do
      info = limiter.info('new_key')
      expect(info[:remaining]).to eq(3)
      expect(info[:capacity]).to eq(3)
    end

    it 'includes reset_at when tokens are depleted' do
      3.times { limiter.allow?('user1') }
      info = limiter.info('user1')
      expect(info[:reset_at]).to be_a(Float)
    end

    it 'returns nil reset_at when at full capacity' do
      info = limiter.info('new_key')
      expect(info[:reset_at]).to be_nil
    end
  end

  describe '#stats' do
    it 'returns zeroes for an unused key' do
      stats = limiter.stats('user1')
      expect(stats).to eq({ allowed: 0, rejected: 0 })
    end

    it 'counts allowed requests' do
      2.times { limiter.allow?('user1') }
      stats = limiter.stats('user1')
      expect(stats[:allowed]).to eq(2)
    end

    it 'counts rejected requests' do
      3.times { limiter.allow?('user1') }
      2.times { limiter.allow?('user1') }
      stats = limiter.stats('user1')
      expect(stats[:rejected]).to eq(2)
    end

    it 'tracks keys independently' do
      3.times { limiter.allow?('user1') }
      limiter.allow?('user1')
      limiter.allow?('user2')
      expect(limiter.stats('user1')[:rejected]).to eq(1)
      expect(limiter.stats('user2')[:allowed]).to eq(1)
    end

    it 'returns a copy so external mutation is safe' do
      limiter.allow?('user1')
      stats = limiter.stats('user1')
      stats[:allowed] = 999
      expect(limiter.stats('user1')[:allowed]).to eq(1)
    end
  end

  describe '#refund' do
    it 'restores tokens after a refund' do
      3.times { limiter.allow?('user1') }
      expect(limiter.remaining('user1')).to eq(0)
      limiter.refund('user1', amount: 1)
      expect(limiter.remaining('user1')).to eq(1)
    end

    it 'does not refund beyond capacity' do
      limiter.allow?('user1')
      limiter.refund('user1', amount: 5)
      expect(limiter.remaining('user1')).to eq(3)
    end

    it 'defaults amount to 1' do
      2.times { limiter.allow?('user1') }
      limiter.refund('user1')
      expect(limiter.remaining('user1')).to eq(2)
    end

    it 'returns nil' do
      limiter.allow?('user1')
      expect(limiter.refund('user1')).to be_nil
    end
  end

  describe '#on_reject' do
    it 'fires callback when a request is rejected' do
      rejected_keys = []
      limiter.on_reject { |key| rejected_keys << key }
      3.times { limiter.allow?('user1') }
      limiter.allow?('user1')
      expect(rejected_keys).to eq(['user1'])
    end

    it 'does not fire on allowed requests' do
      called = false
      limiter.on_reject { |_key| called = true }
      limiter.allow?('user1')
      expect(called).to be false
    end

    it 'fires for each rejection' do
      count = 0
      limiter.on_reject { |_key| count += 1 }
      3.times { limiter.allow?('user1') }
      3.times { limiter.allow?('user1') }
      expect(count).to eq(3)
    end

    it 'returns self for chaining' do
      result = limiter.on_reject { |_key| nil }
      expect(result).to be(limiter)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent access without errors' do
      bucket = described_class.new(rate: 1000, capacity: 100)
      threads = Array.new(10) do
        Thread.new { 20.times { bucket.allow?('shared') } }
      end
      threads.each(&:join)
      expect(bucket.remaining('shared')).to be >= 0
    end
  end
end

RSpec.describe Philiprehberger::RateLimiter do
  describe 'SlidingWindow#wait_time' do
    it 'returns 0 when requests are allowed' do
      limiter = described_class.sliding_window(limit: 10, window: 60)
      expect(limiter.wait_time).to eq(0.0)
    end

    it 'returns positive value when limit is reached' do
      limiter = described_class.sliding_window(limit: 2, window: 60)
      limiter.allow?(:default)
      limiter.allow?(:default)
      expect(limiter.wait_time).to be > 0
    end
  end

  describe 'SlidingWindow#window_reset_at' do
    it 'returns nil when no requests made' do
      limiter = described_class.sliding_window(limit: 10, window: 60)
      expect(limiter.window_reset_at).to be_nil
    end

    it 'returns a Time after requests' do
      limiter = described_class.sliding_window(limit: 10, window: 60)
      limiter.allow?(:default)
      result = limiter.window_reset_at
      expect(result).to be_a(Time)
      expect(result).to be > Time.now
    end
  end

  describe 'TokenBucket#wait_time' do
    it 'returns 0 when tokens are available' do
      limiter = described_class.token_bucket(rate: 10, capacity: 10)
      expect(limiter.wait_time).to eq(0.0)
    end

    it 'returns positive value when bucket is empty' do
      limiter = described_class.token_bucket(rate: 1, capacity: 1)
      limiter.allow?(:default)
      expect(limiter.wait_time).to be > 0
    end

    it 'respects weight parameter' do
      limiter = described_class.token_bucket(rate: 1, capacity: 2)
      limiter.allow?(:default)
      wait = limiter.wait_time(weight: 5)
      expect(wait).to be > 0
    end
  end

  describe '#throttle' do
    it 'executes block and returns allowed hash when under limit (sliding window)' do
      limiter = described_class.sliding_window(limit: 5, window: 60)
      result = limiter.throttle(:user) { 'ok' }
      expect(result).to eq({ allowed: true, value: 'ok' })
    end

    it 'returns rejected hash when over limit (sliding window)' do
      limiter = described_class.sliding_window(limit: 1, window: 60)
      limiter.allow?(:user)
      result = limiter.throttle(:user) { 'should not run' }
      expect(result).to eq({ allowed: false, value: nil })
    end

    it 'executes block and returns allowed hash when under limit (token bucket)' do
      limiter = described_class.token_bucket(rate: 10, capacity: 5)
      result = limiter.throttle(:user) { 42 }
      expect(result).to eq({ allowed: true, value: 42 })
    end

    it 'returns rejected hash when over limit (token bucket)' do
      limiter = described_class.token_bucket(rate: 0.001, capacity: 1)
      limiter.allow?(:user)
      result = limiter.throttle(:user) { 'nope' }
      expect(result).to eq({ allowed: false, value: nil })
    end

    it 'supports weight parameter' do
      limiter = described_class.sliding_window(limit: 3, window: 60)
      result = limiter.throttle(:user, weight: 3) { 'heavy' }
      expect(result).to eq({ allowed: true, value: 'heavy' })

      result2 = limiter.throttle(:user, weight: 1) { 'extra' }
      expect(result2[:allowed]).to be false
    end
  end

  describe '#allow!' do
    it 'returns true when under limit (sliding window)' do
      limiter = described_class.sliding_window(limit: 5, window: 60)
      expect(limiter.allow!(:user)).to be true
    end

    it 'raises RateLimitExceeded when over limit (sliding window)' do
      limiter = described_class.sliding_window(limit: 1, window: 60)
      limiter.allow?(:user)
      expect { limiter.allow!(:user) }.to raise_error(Philiprehberger::RateLimiter::RateLimitExceeded)
    end

    it 'includes the key in the exception' do
      limiter = described_class.sliding_window(limit: 1, window: 60)
      limiter.allow?(:user)
      begin
        limiter.allow!(:user)
      rescue Philiprehberger::RateLimiter::RateLimitExceeded => e
        expect(e.key).to eq(:user)
        expect(e.message).to include('user')
      end
    end

    it 'returns true when under limit (token bucket)' do
      limiter = described_class.token_bucket(rate: 10, capacity: 5)
      expect(limiter.allow!(:api)).to be true
    end

    it 'raises RateLimitExceeded when over limit (token bucket)' do
      limiter = described_class.token_bucket(rate: 0.001, capacity: 1)
      limiter.allow?(:api)
      expect { limiter.allow!(:api) }.to raise_error(Philiprehberger::RateLimiter::RateLimitExceeded)
    end
  end

  describe '#keys' do
    it 'returns empty array initially (sliding window)' do
      limiter = described_class.sliding_window(limit: 5, window: 60)
      expect(limiter.keys).to eq([])
    end

    it 'returns tracked keys (sliding window)' do
      limiter = described_class.sliding_window(limit: 5, window: 60)
      limiter.allow?(:user_a)
      limiter.allow?(:user_b)
      expect(limiter.keys).to contain_exactly('user_a', 'user_b')
    end

    it 'returns tracked keys (token bucket)' do
      limiter = described_class.token_bucket(rate: 10, capacity: 50)
      limiter.allow?(:key_1)
      limiter.allow?(:key_2)
      expect(limiter.keys).to contain_exactly('key_1', 'key_2')
    end

    it 'reflects cleared keys after clear' do
      limiter = described_class.sliding_window(limit: 5, window: 60)
      limiter.allow?(:user)
      limiter.clear
      expect(limiter.keys).to eq([])
    end
  end
end
