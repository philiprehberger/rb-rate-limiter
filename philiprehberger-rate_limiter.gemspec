# frozen_string_literal: true

require_relative "lib/philiprehberger/rate_limiter/version"

Gem::Specification.new do |spec|
  spec.name = "philiprehberger-rate_limiter"
  spec.version = Philiprehberger::RateLimiter::VERSION
  spec.authors = ["Philip Rehberger"]
  spec.email = ["me@philiprehberger.com"]

  spec.summary = "In-memory rate limiter with sliding window and token bucket"
  spec.description = "A zero-dependency Ruby gem for rate limiting with sliding window and " \
                     "token bucket algorithms, per-key tracking, and thread safety."
  spec.homepage = "https://github.com/philiprehberger/rb-rate-limiter"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  end

  spec.require_paths = ["lib"]
end
