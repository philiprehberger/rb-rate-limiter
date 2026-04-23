# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::RateLimiter::Noop do
  let(:limiter) { described_class.new }

  it 'always allows requests' do
    1000.times { expect(limiter.allow?('k')).to be true }
  end

  it 'never raises from allow!' do
    expect(limiter.allow!('k')).to be true
  end

  it 'reports infinite remaining quota' do
    expect(limiter.remaining('k')).to eq(Float::INFINITY)
  end

  it 'always reports 0 for used' do
    1000.times { limiter.allow?('k') }
    expect(limiter.used('k')).to eq(0)
  end

  it 'defaults the used key to :default' do
    expect(limiter.used).to eq(0)
  end

  it 'throttles blocks as allowed' do
    result = limiter.throttle('k') { 42 }
    expect(result).to eq(allowed: true, value: 42)
  end

  it 'returns empty keys list' do
    limiter.allow?('k')
    expect(limiter.keys).to eq([])
  end

  it 'returns a stable info hash' do
    info = limiter.info('k')
    expect(info[:limit]).to eq(Float::INFINITY)
    expect(info[:used]).to eq(0)
  end

  it 'is reachable via RateLimiter.noop' do
    expect(Philiprehberger::RateLimiter.noop).to be_a(described_class)
  end

  it 'always reports 0.0 for retry_after' do
    expect(limiter.retry_after('k')).to eq(0.0)
  end

  it 'defaults the retry_after key to :default' do
    expect(limiter.retry_after).to eq(0.0)
  end
end
