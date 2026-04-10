# philiprehberger-rate_limiter

[![Tests](https://github.com/philiprehberger/rb-rate-limiter/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-rate-limiter/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-rate_limiter.svg)](https://rubygems.org/gems/philiprehberger-rate_limiter)
[![Last updated](https://img.shields.io/github/last-commit/philiprehberger/rb-rate-limiter)](https://github.com/philiprehberger/rb-rate-limiter/commits/main)

In-memory rate limiter with sliding window and token bucket

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-rate_limiter"
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

### Weighted Requests

Consume multiple tokens per request for expensive operations:

```ruby
limiter.allow?("user:123", weight: 5) # consumes 5 tokens
limiter.allow?("user:123", weight: 1) # consumes 1 token (default)
```

### Inspecting Usage

```ruby
info = limiter.info("user:123")
# Sliding window:
# => { remaining: 98, reset_at: 1710000060.5, limit: 100, window: 60, used: 2 }
# Token bucket:
# => { remaining: 48, reset_at: 1710000000.2, capacity: 50, rate: 10.0, tokens: 48.3 }
```

The `reset_at` value is a monotonic timestamp suitable for computing X-RateLimit-Reset headers. It is `nil` when the key has no usage or is at full capacity.

### Per-Key Stats

Track allowed and rejected request counts:

```ruby
limiter.stats("user:123")
# => { allowed: 42, rejected: 3 }
```

### Quota Refund

Return tokens when a downstream operation fails (so the failed request does not count):

```ruby
if limiter.allow?("user:123")
  begin
    make_api_call
  rescue ApiError
    limiter.refund("user:123", amount: 1)
  end
end
```

### On-Reject Callback

Register a hook for logging or alerting when requests are rejected:

```ruby
limiter.on_reject do |key|
  logger.warn("Rate limit exceeded for #{key}")
end
```

The method returns `self` for chaining:

```ruby
limiter = Philiprehberger::RateLimiter
  .sliding_window(limit: 100, window: 60)
  .on_reject { |key| logger.warn("Rejected: #{key}") }
```

### Throttle (Execute if Allowed)

```ruby
result = limiter.throttle("user:123") { make_api_call }
result[:allowed]  # => true
result[:value]    # => the return value of make_api_call

# When rejected:
result = limiter.throttle("user:123") { make_api_call }
result[:allowed]  # => false
result[:value]    # => nil
```

### Allow! (Raise on Rejection)

```ruby
limiter.allow!("user:123")  # => true, or raises RateLimitExceeded
```

### Listing Tracked Keys

```ruby
limiter.keys  # => ["user:123", "user:456"]
```

### Wait Time

Check how long until the next request is allowed:

```ruby
limiter = Philiprehberger::RateLimiter.sliding_window(limit: 100, window: 60)
limiter.wait_time  # => 0.0 (allowed now)

# After hitting the limit:
limiter.wait_time  # => 12.5 (seconds to wait)
```

### Window Reset

```ruby
limiter.window_reset_at  # => 2026-04-01 12:01:00 +0000 (Time when window expires)
```

### Resetting a Key

```ruby
limiter.reset("user:123")  # clear state for one key
limiter.clear              # clear state for all keys
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
| `#allow?(key, weight: 1)` | Check and consume token(s); returns `true`/`false` |
| `#allow!(key, weight: 1)` | Like `allow?` but raises `RateLimitExceeded` on rejection |
| `#throttle(key, weight: 1) { }` | Execute block if allowed; returns `{ allowed:, value: }` |
| `#peek(key)` | Check availability without consuming |
| `#remaining(key)` | Return remaining request/token count |
| `#reset(key)` | Clear all state for a key |
| `#clear` | Clear all state for every tracked key |
| `#keys` | Return all currently tracked keys |
| `#info(key)` | Return usage info hash (remaining, reset_at, limit/capacity, used/tokens) |
| `#stats(key)` | Return `{ allowed:, rejected: }` counters for a key |
| `#wait_time(key)` | Seconds until next request is allowed (0 if now). `TokenBucket` also accepts `weight:` keyword argument |
| `SlidingWindow#window_reset_at(key)` | Time when current window expires |
| `#refund(key, amount: 1)` | Return tokens/slots on error |
| `#on_reject { \|key\| }` | Register a callback for rejected requests |
| `SlidingWindow#limit` | Return the configured request limit |
| `SlidingWindow#window` | Return the configured window duration (seconds) |
| `TokenBucket#rate` | Return the configured refill rate (tokens/sec) |
| `TokenBucket#capacity` | Return the configured token capacity |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

If you find this project useful:

⭐ [Star the repo](https://github.com/philiprehberger/rb-rate-limiter)

🐛 [Report issues](https://github.com/philiprehberger/rb-rate-limiter/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

💡 [Suggest features](https://github.com/philiprehberger/rb-rate-limiter/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)

❤️ [Sponsor development](https://github.com/sponsors/philiprehberger)

🌐 [All Open Source Projects](https://philiprehberger.com/open-source-packages)

💻 [GitHub Profile](https://github.com/philiprehberger)

🔗 [LinkedIn Profile](https://www.linkedin.com/in/philiprehberger)

## License

[MIT](LICENSE)
