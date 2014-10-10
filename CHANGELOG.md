# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
