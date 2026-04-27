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

### No-op Limiter

A limiter that always allows requests — useful in test environments or when a feature is behind a kill-switch.

```ruby
limiter = Philiprehberger::RateLimiter.noop
limiter.allow?("anyone")    # => true
limiter.remaining("anyone") # => Float::INFINITY
```

### Peeking Without Consuming

```ruby
limiter.peek("user:123")      # => true/false (does not consume)
limiter.remaining("user:123") # => number of remaining requests/tokens
```

### Batch Checks

Check several keys in one call. The whole batch runs under a single mutex acquisition, so stats and quota updates are consistent across keys.

```ruby
limiter = Philiprehberger::RateLimiter.sliding_window(limit: 1, window: 60)
limiter.allow?('user:1')
limiter.allow_batch(['user:1', 'user:2', 'user:3'])
# => { 'user:1' => false, 'user:2' => true, 'user:3' => true }
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

### Inspect consumed count

Call `used(key)` for a cheap integer count of currently consumed slots/tokens — it complements `remaining(key)` without allocating an `info` hash.

```ruby
limiter = Philiprehberger::RateLimiter.sliding_window(limit: 100, window: 60)
3.times { limiter.allow?("user:123") }
limiter.used("user:123")      # => 3
limiter.remaining("user:123") # => 97
```

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

### Retry-After Header

Use `retry_after(key)` to get the number of seconds until the next request is allowed — ready to emit as an HTTP `Retry-After` header:

```ruby
unless limiter.allow?("user:123")
  response.headers["Retry-After"] = limiter.retry_after("user:123").ceil.to_s
  return too_many_requests
end
```

It returns `0.0` when a request is allowed right now. On `SlidingWindow` it reports when the oldest hit in the window will expire; on `TokenBucket` it reports the time to refill one full token; `Noop` always returns `0.0`.

### Resetting a Key

```ruby
limiter.reset("user:123")  # clear state for one key
limiter.clear              # clear state for all keys
```

### Draining a Key

Forcefully consume all remaining capacity for a key — useful for coordinated lockouts or kill-switch flows:

```ruby
limiter.drain("user:123")    # => 42 (number of slots/tokens drained)
limiter.allow?("user:123")   # => false
limiter.remaining("user:123")# => 0
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
| `RateLimiter.noop` | Create a limiter that always allows requests |
| `#allow?(key, weight: 1)` | Check and consume token(s); returns `true`/`false` |
| `#allow_batch(keys)` | Check many keys in one mutex acquisition; returns `{ key => Boolean }` |
| `#allow!(key, weight: 1)` | Like `allow?` but raises `RateLimitExceeded` on rejection |
| `#throttle(key, weight: 1) { }` | Execute block if allowed; returns `{ allowed:, value: }` |
| `#peek(key)` | Check availability without consuming |
| `#remaining(key)` | Return remaining request/token count |
| `#used(key)` | Return `Integer` count of currently consumed slots/tokens (available on `SlidingWindow`, `TokenBucket`, and `Noop`) |
| `#reset(key)` | Clear all state for a key |
| `#clear` | Clear all state for every tracked key |
| `#keys` | Return all currently tracked keys |
| `#info(key)` | Return usage info hash (remaining, reset_at, limit/capacity, used/tokens) |
| `#stats(key)` | Return `{ allowed:, rejected: }` counters for a key |
| `#wait_time(key)` | Seconds until next request is allowed (0 if now). `TokenBucket` also accepts `weight:` keyword argument |
| `#retry_after(key)` | Seconds until the next allowed request (0.0 if allowed now); ready for the HTTP `Retry-After` header |
| `SlidingWindow#window_reset_at(key)` | Time when current window expires |
| `#refund(key, amount: 1)` | Return tokens/slots on error |
| `#drain(key)` | Forcefully consume all remaining capacity; returns amount drained |
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
