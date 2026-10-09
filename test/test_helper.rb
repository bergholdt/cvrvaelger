# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "vcr"
require "webmock/minitest"
require "cvrvaelger"

env_file = File.expand_path("../.env", __dir__)
if File.file?(env_file)
  File.foreach(env_file) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")

    key, value = line.split("=", 2)
    next unless key && value

    ENV[key] ||= value.delete_prefix("\"").delete_suffix("\"").delete_prefix("'").delete_suffix("'")
  end
end

# VCR for Datafordeler CVR GraphQL. Record against the real API; never hand-write
# cassettes. Local refresh: VCR_RECORD=all. CI uses record: :none. Keys redacted.
module VcrRecordMode
  module_function

  def call
    if ENV["VCR_RECORD"] && !ENV["VCR_RECORD"].empty?
      ENV["VCR_RECORD"].to_sym
    elsif ENV["CI"] && !ENV["CI"].empty?
      :none
    else
      :once
    end
  end
end

VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("cassettes", __dir__)
  config.hook_into :webmock
  config.default_cassette_options = {
    record: VcrRecordMode.call,
    match_requests_on: %i[method uri body],
    decode_compressed_response: true
  }

  config.filter_sensitive_data("<API_KEY>") do
    key = ENV.fetch("CVRVAELGER_API_KEY", nil)
    key = ENV.fetch("DATAFORDELER_API_KEY", nil) if key.nil? || key.empty?
    key.nil? || key.empty? ? "vcr-api-key" : key
  end
end

module LiveClient
  AT = Time.utc(2026, 10, 9, 12, 0, 0)

  def live_client
    Cvrvaelger::Client.new(api_key: ENV["CVRVAELGER_API_KEY"] || ENV["DATAFORDELER_API_KEY"] || "vcr-api-key")
  end
end
