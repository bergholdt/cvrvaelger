# frozen_string_literal: true

module Cvrvaelger
  class Error < StandardError
  end

  # Raised when the Datafordeler CVR API fails, returns invalid JSON, or is unreachable.
  class ProviderError < Error
  end

  # Raised when no API key is configured (no invented demo secret).
  class ConfigurationError < Error
  end
end
