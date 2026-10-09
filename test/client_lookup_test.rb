# frozen_string_literal: true

require "test_helper"
require "json"
require "net/http"

class ClientLookupTest < Minitest::Test
  def test_default_base_url_is_datafordeler_cvr_graphql
    assert_equal "https://graphql.datafordeler.dk/CVR/v1", Cvrvaelger::Client::DEFAULT_BASE_URL
  end

  def test_lookup_returns_nil_for_invalid_cvr_without_http
    client = Cvrvaelger::Client.new(api_key: "test-key", http: ->(*) { flunk "should not call HTTP" })
    assert_nil client.lookup("123")
    assert_nil client.lookup("")
    assert_nil client.lookup(nil)
  end

  def test_lookup_requires_api_key
    previous_cvr = ENV.delete("CVRVAELGER_API_KEY")
    previous_df = ENV.delete("DATAFORDELER_API_KEY")
    error = assert_raises(Cvrvaelger::ConfigurationError) do
      Cvrvaelger::Client.new(api_key: nil, http: ->(*) { flunk "no" }).lookup("25052943")
    end
    assert_match(/CVRVAELGER_API_KEY/, error.message)
  ensure
    ENV["CVRVAELGER_API_KEY"] = previous_cvr if previous_cvr
    ENV["DATAFORDELER_API_KEY"] = previous_df if previous_df
  end

  def test_lookup_maps_graphql_node_to_company
    http = lambda do |uri, request|
      assert_includes uri.to_s, "apiKey=test-key-xx"
      body = JSON.parse(request.body)
      assert_equal "25052943", body.dig("variables", "cvr")

      ok_json(
        "data" => {
          "CVREnhed" => {
            "nodes" => [
              {
                "cvrNummer" => "25052943",
                "navn" => "Example ApS",
                "adresse" => {
                  "vejnavn" => "Titangade",
                  "husnummer" => "11",
                  "postnummer" => "2200",
                  "postdistrikt" => "København N"
                }
              }
            ]
          }
        }
      )
    end

    company = Cvrvaelger::Client.new(api_key: "test-key-xx", http: http).lookup("25 05 29 43")

    assert_equal "25052943", company.cvr
    assert_equal "Example ApS", company.name
    assert_equal "Titangade 11", company.address_line
    assert_equal "2200", company.postal_code
    assert_equal "København N", company.city
    assert_equal "datafordeler_cvr", company.provider
  end

  def test_lookup_returns_nil_when_not_found
    http = lambda do |_uri, _request|
      ok_json("data" => { "CVREnhed" => { "nodes" => [] } })
    end

    assert_nil Cvrvaelger::Client.new(api_key: "k", http: http).lookup("00000000")
  end

  def test_search_by_eight_digits_delegates_to_lookup
    http = lambda do |_uri, _request|
      ok_json(
        "data" => {
          "CVREnhed" => {
            "nodes" => [ { "cvrNummer" => "25052943", "navn" => "Example ApS" } ]
          }
        }
      )
    end

    hits = Cvrvaelger::Client.new(api_key: "k", http: http).search("25052943")
    assert_equal 1, hits.size
    assert_equal "Example ApS", hits.first.name
  end

  def test_raises_provider_error_on_http_failure
    http = lambda do |_uri, _request|
      Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized").tap do |response|
        response.define_singleton_method(:body) { "{}" }
      end
    end

    error = assert_raises(Cvrvaelger::ProviderError) do
      Cvrvaelger::Client.new(api_key: "k", http: http).lookup("25052943")
    end
    assert_match(/401/, error.message)
  end

  private

    def ok_json(payload)
      Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
        response.define_singleton_method(:body) { JSON.generate(payload) }
      end
    end
end
