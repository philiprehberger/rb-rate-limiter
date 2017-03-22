# Changelog

## 0.3.1

- Fix RuboCop Style/StringLiterals violations in gemspec

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-03-17

### Added
- Weighted requests: `allow?(key, weight: n)` to consume multiple tokens per request
- Per-key stats: `stats(key)` returns `{ allowed:, rejected: }` counters
- Quota refund: `refund(key, amount: 1)` to return tokens on failed operations
- On-reject callback: `on_reject { |key| ... }` hook for logging/alerting
- `reset_at` field in `info(key)` response for X-RateLimit-Reset headers
- `StatsTracking` module for shared stats and callback logic

## [0.2.2]

- Add License badge to README
- Add bug_tracker_uri to gemspec

## [Unreleased]

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
