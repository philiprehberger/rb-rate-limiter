# philiprehberger-rate_limiter

[![Tests](https://github.com/philiprehberger/rb-rate-limiter/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-rate-limiter/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-rate_limiter.svg)](https://rubygems.org/gems/philiprehberger-rate_limiter)
[![License](https://img.shields.io/github/license/philiprehberger/rb-rate-limiter)](LICENSE)

In-memory rate limiter with sliding window and token bucket algorithms, per-key tracking, and thread safety.

> **Note:** This is a single-process, in-memory rate limiter. It does not share state across processes or servers. For distributed rate limiting, use a centralized store like Redis.

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-rate_limiter"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install philiprehberger-rate_limiter
```

## Usage

```ruby
require "philiprehberger/rate_limiter"
```

### Sliding Window

Limits the number of requests within a rolling time window.

```ruby
limiter = Philiprehberger::RateLimiter.sliding_window(limit: 100, window: 60)

if limiter.allow?("user:123")
  # Request is allowed
else
  # Rate limit exceeded
end
```

### Token Bucket

Allows bursts up to a capacity, refilling at a steady rate.

```ruby
limiter = Philiprehberger::RateLimiter.token_bucket(rate: 10, capacity: 50)

if limiter.allow?("api:key")
  # Request is allowed
else
  # Rate limit exceeded
end
```

### Peeking Without Consuming

```ruby
limiter.peek("user:123")      # => true/false (does not consume)
limiter.remaining("user:123") # => number of remaining requests/tokens
```

### Inspecting Usage

```ruby
info = limiter.info("user:123")
# => { remaining: 98, limit: 100, window: 60, used: 2 }  (sliding window)
# => { remaining: 48, capacity: 50, rate: 10.0, tokens: 48.3 }  (token bucket)
```

### Resetting a Key

```ruby
limiter.reset("user:123")
```

### Sliding Window vs Token Bucket

| Feature | SlidingWindow | TokenBucket |
|---------|---------------|-------------|
| Best for | Fixed request counts per window | Allowing bursts with steady refill |
| Parameters | `limit`, `window` (seconds) | `rate` (tokens/sec), `capacity` |
| Burst behavior | No bursting beyond limit | Allows bursts up to capacity |
| Memory | Stores timestamps per request | Stores one float + timestamp per key |

## API

| Method | Description |
|--------|-------------|
| `RateLimiter.sliding_window(limit:, window:)` | Create a sliding window limiter |
| `RateLimiter.token_bucket(rate:, capacity:)` | Create a token bucket limiter |
| `#allow?(key)` | Check and consume one request/token; returns `true`/`false` |
| `#peek(key)` | Check availability without consuming |
| `#remaining(key)` | Return remaining request/token count |
| `#reset(key)` | Clear all state for a key |
| `#info(key)` | Return usage info hash (remaining, limit/capacity, used/tokens) |
| `SlidingWindow#limit` | Return the configured request limit |
| `SlidingWindow#window` | Return the configured window duration (seconds) |
| `TokenBucket#rate` | Return the configured refill rate (tokens/sec) |
| `TokenBucket#capacity` | Return the configured token capacity |

## Development

```bash
bundle install
bundle exec rspec      # Run tests
bundle exec rubocop    # Check code style
```

## License

MIT
