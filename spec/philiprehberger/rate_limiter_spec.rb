# frozen_string_literal: true

require "spec_helper"

RSpec.describe Philiprehberger::RateLimiter do
  it "has a version number" do
    expect(described_class::VERSION).not_to be_nil
  end

  describe ".sliding_window" do
    it "returns a SlidingWindow instance" do
      limiter = described_class.sliding_window(limit: 5, window: 60)
      expect(limiter).to be_a(described_class::SlidingWindow)
    end
  end

  describe ".token_bucket" do
    it "returns a TokenBucket instance" do
      limiter = described_class.token_bucket(rate: 1, capacity: 5)
      expect(limiter).to be_a(described_class::TokenBucket)
    end
  end
end

RSpec.describe Philiprehberger::RateLimiter::SlidingWindow do
  subject(:limiter) { described_class.new(limit: 3, window: 1) }

  describe "#allow?" do
    it "allows requests within the limit" do
      3.times { expect(limiter.allow?("user1")).to be true }
    end

    it "blocks requests over the limit" do
      3.times { limiter.allow?("user1") }
      expect(limiter.allow?("user1")).to be false
    end

    it "tracks keys independently" do
      3.times { limiter.allow?("user1") }
      expect(limiter.allow?("user2")).to be true
    end

    it "resets after the window expires" do
      3.times { limiter.allow?("user1") }
      sleep(1.1)
      expect(limiter.allow?("user1")).to be true
    end
  end

  describe "#peek" do
    it "returns true when requests are available" do
      expect(limiter.peek("user1")).to be true
    end

    it "returns false when limit is reached" do
      3.times { limiter.allow?("user1") }
      expect(limiter.peek("user1")).to be false
    end

    it "does not consume a request" do
      limiter.peek("user1")
      expect(limiter.remaining("user1")).to eq(3)
    end
  end

  describe "#remaining" do
    it "returns the full limit initially" do
      expect(limiter.remaining("user1")).to eq(3)
    end

    it "decreases after each allowed request" do
      2.times { limiter.allow?("user1") }
      expect(limiter.remaining("user1")).to eq(1)
    end
  end

  describe "#reset" do
    it "clears state for a key" do
      3.times { limiter.allow?("user1") }
      limiter.reset("user1")
      expect(limiter.remaining("user1")).to eq(3)
    end
  end

  describe "#limit" do
    it "returns the configured limit" do
      expect(limiter.limit).to eq(3)
    end
  end

  describe "#window" do
    it "returns the configured window" do
      expect(limiter.window).to eq(1)
    end
  end

  describe "#info" do
    it "returns usage info for a key" do
      2.times { limiter.allow?("user1") }
      info = limiter.info("user1")
      expect(info[:remaining]).to eq(1)
      expect(info[:limit]).to eq(3)
      expect(info[:window]).to eq(1)
      expect(info[:used]).to eq(2)
    end

    it "returns full limit for unknown key" do
      info = limiter.info("new_key")
      expect(info[:remaining]).to eq(3)
      expect(info[:used]).to eq(0)
    end
  end

  describe "thread safety" do
    it "handles concurrent access without errors" do
      window_limiter = described_class.new(limit: 100, window: 10)
      threads = Array.new(10) do
        Thread.new { 20.times { window_limiter.allow?("shared") } }
      end
      threads.each(&:join)
      expect(window_limiter.remaining("shared")).to be >= 0
    end
  end
end

RSpec.describe Philiprehberger::RateLimiter::TokenBucket do
  subject(:limiter) { described_class.new(rate: 10, capacity: 3) }

  describe "#allow?" do
    it "allows requests within capacity" do
      3.times { expect(limiter.allow?("user1")).to be true }
    end

    it "blocks when tokens are exhausted" do
      3.times { limiter.allow?("user1") }
      expect(limiter.allow?("user1")).to be false
    end

    it "tracks keys independently" do
      3.times { limiter.allow?("user1") }
      expect(limiter.allow?("user2")).to be true
    end

    it "refills tokens over time" do
      3.times { limiter.allow?("user1") }
      sleep(0.2)
      expect(limiter.allow?("user1")).to be true
    end
  end

  describe "#peek" do
    it "returns true when tokens are available" do
      expect(limiter.peek("user1")).to be true
    end

    it "returns false when tokens are exhausted" do
      3.times { limiter.allow?("user1") }
      expect(limiter.peek("user1")).to be false
    end

    it "does not consume a token" do
      limiter.peek("user1")
      expect(limiter.remaining("user1")).to eq(3)
    end
  end

  describe "#remaining" do
    it "returns the full capacity initially" do
      expect(limiter.remaining("user1")).to eq(3)
    end

    it "decreases after consumption" do
      2.times { limiter.allow?("user1") }
      expect(limiter.remaining("user1")).to eq(1)
    end
  end

  describe "#reset" do
    it "clears state for a key" do
      3.times { limiter.allow?("user1") }
      limiter.reset("user1")
      expect(limiter.remaining("user1")).to eq(3)
    end
  end

  describe "#rate" do
    it "returns the configured rate" do
      expect(limiter.rate).to eq(10.0)
    end
  end

  describe "#capacity" do
    it "returns the configured capacity" do
      expect(limiter.capacity).to eq(3.0)
    end
  end

  describe "#info" do
    it "returns usage info for a key" do
      2.times { limiter.allow?("user1") }
      info = limiter.info("user1")
      expect(info[:remaining]).to eq(1)
      expect(info[:capacity]).to eq(3)
      expect(info[:rate]).to eq(10.0)
      expect(info[:tokens]).to be_a(Float)
    end

    it "returns full capacity for unknown key" do
      info = limiter.info("new_key")
      expect(info[:remaining]).to eq(3)
      expect(info[:capacity]).to eq(3)
    end
  end

  describe "thread safety" do
    it "handles concurrent access without errors" do
      bucket = described_class.new(rate: 1000, capacity: 100)
      threads = Array.new(10) do
        Thread.new { 20.times { bucket.allow?("shared") } }
      end
      threads.each(&:join)
      expect(bucket.remaining("shared")).to be >= 0
    end
  end
end
