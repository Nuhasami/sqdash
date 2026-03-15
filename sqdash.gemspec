# frozen_string_literal: true

require_relative "lib/sqdash/version"

Gem::Specification.new do |spec|
  spec.name = "sqdash"
  spec.version = Sqdash::VERSION
  spec.authors = ["Nuha"]
  spec.email = ["nuha.sami@hey.com"]

  spec.summary = "A terminal dashboard for Rails 8's Solid Queue"
  spec.description = "sqdash is a fast, keyboard-driven TUI for monitoring and managing Solid Queue jobs. " \
                     "View pending, failed, and completed jobs, retry or discard failures, filter, sort, " \
                     "and navigate — all without leaving your terminal."

  spec.homepage = "https://github.com/nuhasami/sqdash"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nuhasami/sqdash"
  spec.metadata["changelog_uri"] = "https://github.com/nuhasami/sqdash/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", "~> 8.0"

  # Database adapters — users install the one they need.
  # At least one is required at runtime.
  # Example: gem install sqdash && gem install pg

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
