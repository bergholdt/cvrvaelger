# frozen_string_literal: true

require_relative "lib/cvrvaelger/version"

Gem::Specification.new do |spec|
  spec.name = "cvrvaelger"
  spec.version = Cvrvaelger::VERSION
  spec.authors = ["Rasmus Bergholdt"]
  spec.email = ["rasmus.bergholdt@gmail.com"]

  spec.summary = "Ruby client for Danish CVR company lookup via Datafordeler GraphQL."
  spec.description = <<~DESC
    HTTP client for Det Centrale Virksomhedsregister (CVR) on Datafordeler GraphQL:
    verify an 8-digit CVR number or exact registered name and return the company
    name plus light address fields for picker UX. No Rails dependency.
  DESC
  spec.homepage = "https://github.com/bergholdt/cvrvaelger"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bergholdt/cvrvaelger/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "https://github.com/bergholdt/cvrvaelger/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/bergholdt/cvrvaelger/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.start_with?(*%w[bin/ test/ .git .github Gemfile Rakefile AGENTS.md])
    end
  end
  spec.require_paths = ["lib"]
end
