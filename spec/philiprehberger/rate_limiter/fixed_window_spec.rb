# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::RateLimiter::FixedWindow do
  subject(:limiter) { described_class.new(limit: 3, window: 60) }

  describe 'factory' do
    it 'is reachable via RateLimiter.fixed_window' do
      built = Philiprehberger::RateLimiter.fixed_window(limit: 3, window: 60)
      expect(built).to be_a(described_class)
    end
  end

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

    it 'resets the counter when the window elapses (stubbed clock)' do
      now = 1_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(now)
      3.times { limiter.allow?('user1') }
      expect(limiter.allow?('user1')).to be false

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(now + 61)
      expect(limiter.allow?('user1')).to be true
    end

    it 'consumes multiple slots with weight' do
      expect(limiter.allow?('user1', weight: 2)).to be true
      expect(limiter.remaining('user1')).to eq(1)
    end

    it 'rejects when weight exceeds remaining' do
      limiter.allow?('user1', weight: 2)
      expect(limiter.allow?('user1', weight: 2)).to be false
    end
  end

  describe '#allow_batch' do
    it 'returns a Hash with each input key' do
      result = limiter.allow_batch(%w[a b c])
      expect(result.keys).to eq(%w[a b c])
      expect(result.values).to all(be true)
    end

    it 'returns mixed results when limits are exceeded' do
      3.times { limiter.allow?('user1') }
      result = limiter.allow_batch(%w[user1 user2])
      expect(result).to eq({ 'user1' => false, 'user2' => true })
    end
  end

  describe '#peek' do
    it 'returns true when capacity is available' do
      expect(limiter.peek('user1')).to be true
    end

    it 'returns false when the limit is reached' do
      3.times { limiter.allow?('user1') }
      expect(limiter.peek('user1')).to be false
    end

    it 'does not consume a slot' do
      limiter.peek('user1')
      expect(limiter.remaining('user1')).to eq(3)
    end
  end

  describe '#remaining and #used' do
    it 'reports full limit and zero used initially' do
      expect(limiter.remaining('user1')).to eq(3)
      expect(limiter.used('user1')).to eq(0)
    end

    it 'decreases remaining and increases used after calls' do
      2.times { limiter.allow?('user1') }
      expect(limiter.remaining('user1')).to eq(1)
      expect(limiter.used('user1')).to eq(2)
    end
  end

  describe '#reset and #clear' do
    it 'reset clears a single key' do
      3.times { limiter.allow?('user1') }
      limiter.reset('user1')
      expect(limiter.remaining('user1')).to eq(3)
    end

    it 'clear resets all keys and stats' do
      limiter.allow?('user1')
      limiter.clear
      expect(limiter.keys).to eq([])
    end
  end

  describe '#info' do
    it 'returns usage info for a key' do
      2.times { limiter.allow?('user1') }
      info = limiter.info('user1')
      expect(info[:remaining]).to eq(1)
      expect(info[:limit]).to eq(3)
      expect(info[:window]).to eq(60)
      expect(info[:used]).to eq(2)
      expect(info[:reset_at]).to be_a(Float)
    end

    it 'returns nil reset_at for an unused key' do
      expect(limiter.info('new_key')[:reset_at]).to be_nil
    end
  end

  describe '#info_batch' do
    it 'returns info for each key' do
      2.times { limiter.allow?('user1') }
      result = limiter.info_batch(%w[user1 user2])
      expect(result['user1'][:used]).to eq(2)
      expect(result['user2'][:used]).to eq(0)
    end
  end

  describe '#refund' do
    it 'restores capacity after a refund' do
      3.times { limiter.allow?('user1') }
      limiter.refund('user1', amount: 1)
      expect(limiter.remaining('user1')).to eq(1)
    end

    it 'does not refund below zero used' do
      limiter.allow?('user1')
      limiter.refund('user1', amount: 5)
      expect(limiter.remaining('user1')).to eq(3)
    end

    it 'returns nil' do
      limiter.allow?('user1')
      expect(limiter.refund('user1')).to be_nil
    end
  end

  describe '#wait_time' do
    it 'returns 0 when under the limit' do
      expect(limiter.wait_time('user1')).to eq(0.0)
    end

    it 'returns a positive value bounded by the window when at the limit (stubbed clock)' do
      now = 2_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(now)
      3.times { limiter.allow?('user1') }
      expect(limiter.wait_time('user1')).to be_within(0.0001).of(60)
    end

    it 'defaults the key to :default' do
      expect(limiter.wait_time).to eq(0.0)
    end
  end

  describe '#retry_after' do
    it 'returns 0.0 when under the limit' do
      expect(limiter.retry_after('user1')).to eq(0.0)
    end

    it 'returns the time to the window edge when full (stubbed clock)' do
      now = 5_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(now)
      3.times { limiter.allow?('user1') }

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(now + 20)
      expect(limiter.retry_after('user1')).to be_within(0.0001).of(40)
    end

    it 'defaults the key to :default' do
      expect(limiter.retry_after).to eq(0.0)
    end
  end

  describe 'shared StatsTracking surface' do
    it 'counts allowed and rejected requests' do
      3.times { limiter.allow?('user1') }
      2.times { limiter.allow?('user1') }
      expect(limiter.stats('user1')).to eq({ allowed: 3, rejected: 2 })
    end

    it 'raises RateLimitExceeded from allow! when over the limit' do
      3.times { limiter.allow?('user1') }
      expect { limiter.allow!('user1') }.to raise_error(Philiprehberger::RateLimiter::RateLimitExceeded)
    end

    it 'throttles a block when allowed' do
      expect(limiter.throttle('user1') { 'ok' }).to eq({ allowed: true, value: 'ok' })
    end

    it 'lists tracked keys' do
      limiter.allow?('user1')
      expect(limiter.keys).to contain_exactly('user1')
    end

    it 'fires the on_reject callback' do
      rejected = []
      limiter.on_reject { |key| rejected << key }
      3.times { limiter.allow?('user1') }
      limiter.allow?('user1')
      expect(rejected).to eq(['user1'])
    end
  end

  describe '#block' do
    it 'acquires immediately when capacity is available' do
      expect(limiter).not_to receive(:sleep)
      expect(limiter.block('user1', timeout: 5)).to be true
    end

    it 'waits for the window to roll then acquires (stubbed clock)' do
      one = described_class.new(limit: 1, window: 10)
      clock = 30_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock }
      one.allow?('user1') # fill the window at t=30_000
      allow(one).to receive(:sleep) { |secs| clock += secs }

      expect(one.block('user1', timeout: 30)).to be true
    end

    it 'returns false when the timeout elapses first (stubbed clock)' do
      one = described_class.new(limit: 1, window: 100)
      clock = 40_000.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock }
      one.allow?('user1')
      allow(one).to receive(:sleep) { |secs| clock += secs }

      expect(one.block('user1', timeout: 1)).to be false
    end
  end

  describe 'thread safety' do
    it 'handles concurrent access without errors' do
      big = described_class.new(limit: 100, window: 10)
      threads = Array.new(10) { Thread.new { 20.times { big.allow?('shared') } } }
      threads.each(&:join)
      expect(big.remaining('shared')).to be >= 0
    end
  end
end
