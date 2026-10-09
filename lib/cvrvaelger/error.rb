# frozen_string_literal: true

module Cvrvaelger
  Error = Class.new(StandardError)
  # Raised when the Datafordeler CVR API fails, returns invalid JSON, or is unreachable.
  ProviderError = Class.new(Error)
  # Raised when no API key is configured (no invented demo secret).
  ConfigurationError = Class.new(Error)
end
