# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.11.0] - 2026-04-26

### Added
- `#allow_batch(keys)` on `SlidingWindow`, `TokenBucket`, and `Noop` — check many keys in a single mutex acquisition, returning `{ key => Boolean }`

## [0.10.0] - 2026-04-18

### Added
- `#used(key)` on `SlidingWindow`, `TokenBucket`, and `Noop` — returns an `Integer` count of currently consumed slots/tokens; complements `#remaining` without allocating an `#info` hash

## [0.9.0] - 2026-04-16

### Added
- `retry_after(key)` on `SlidingWindow`, `TokenBucket`, and `Noop` — returns seconds until the next allowed request (0 if allowed now). Suitable for the HTTP `Retry-After` header.

## [0.8.0] - 2026-04-16

### Added
- `#drain(key)` on `SlidingWindow`, `TokenBucket`, and `Noop` — forcefully consumes all remaining capacity for a key and returns the amount drained

## [0.7.0] - 2026-04-15

### Added
- `RateLimiter.noop` — no-op limiter that always allows requests, matching the limiter API for test and rollout scenarios

## [0.6.0] - 2026-04-09

### Added
- `#throttle(key, weight:) { ... }` to execute a block only when allowed, returning `{ allowed:, value: }`
- `#allow!(key, weight:)` that raises `RateLimitExceeded` on rejection
- `#keys` to list all currently tracked keys
- `RateLimitExceeded` error class with `key` accessor

## [0.5.2] - 2026-04-07

### Added
- `#clear` method on `SlidingWindow` and `TokenBucket` to reset state and stats for all keys in one call

### Changed
- Removed non-standard "Thread Safety" section and single-process blockquote from README to match the standard 10-section template

## [0.5.1] - 2026-04-05

### Fixed
- Merged duplicate CHANGELOG entries for v0.3.2
- Documented `weight:` parameter on `TokenBucket#wait_time` in README
- Added thread-safety note to README

## [0.5.0] - 2026-04-04

### Added
- `gem-version` field in bug report issue template
- "Alternatives considered" textarea in feature request issue template

### Changed
- `ruby-version` field in bug report issue template is now required

## [0.4.0] - 2026-04-01

### Added
- `#wait_time(key)` for checking seconds until next allowed request
- `SlidingWindow#window_reset_at(key)` for getting window expiry time

## [0.3.7] - 2026-03-31

### Added
- Add GitHub issue templates, dependabot config, and PR template

## [0.3.6] - 2026-03-31

### Changed
- Standardize README badges, support section, and license format

## [0.3.5] - 2026-03-26

### Changed

- Add Sponsor badge and fix License link format in README

## [0.3.4] - 2026-03-24

### Fixed
- Fix README one-liner to remove trailing period and match gemspec summary

## [0.3.3] - 2026-03-24

### Fixed
- Remove inline comments from Development section to match template

## [0.3.2] - 2026-03-22

### Changed
- Update rubocop configuration for Windows compatibility

### Fixed
- Standardize Installation section in README

## [0.3.1] - 2026-03-18

### Fixed
- Fix RuboCop Style/StringLiterals violations in gemspec

## [0.3.0] - 2026-03-17

### Added
- Weighted requests: `allow?(key, weight: n)` to consume multiple tokens per request
- Per-key stats: `stats(key)` returns `{ allowed:, rejected: }` counters
- Quota refund: `refund(key, amount: 1)` to return tokens on failed operations
- On-reject callback: `on_reject { |key| ... }` hook for logging/alerting
- `reset_at` field in `info(key)` response for X-RateLimit-Reset headers
- `StatsTracking` module for shared stats and callback logic

## [0.2.2] - 2026-03-16

### Changed
- Add License badge to README
- Add bug_tracker_uri to gemspec

## [0.2.1] - 2026-03-12

### Fixed
- Re-release with no code changes (RubyGems publish fix)

## [0.2.0] - 2026-03-12

### Added
- Read-only accessors: `limit`, `window` on SlidingWindow; `rate`, `capacity` on TokenBucket
- `info(key)` method on both strategies returning remaining quota, limits, and usage stats
- Single-process usage note in README
- SlidingWindow vs TokenBucket comparison table in README

## [0.1.0] - 2026-03-10

### Added
- Initial release
- Sliding window rate limiting with per-key tracking
- Token bucket rate limiting with automatic refill
- Thread-safe operations with Mutex
- `allow?` to check and consume in one call
- `peek` to check without consuming
- `remaining` to query available quota
- `reset` to clear state for a key
- Convenience factory methods on the module
