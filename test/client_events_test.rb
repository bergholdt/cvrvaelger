# frozen_string_literal: true

require "test_helper"
require "json"
require "net/http"

class ClientEventsTest < Minitest::Test
  AT = Time.utc(2026, 10, 9, 12, 0, 0)
  STAMP = "2026-10-09T12:00:00.000000Z"

  def test_events_sends_gt_where_filter
    http = lambda do |_uri, request|
      body = JSON.parse(request.body)
      query = body.fetch("query")

      assert_includes query, "CVR_Events"
      assert_includes query, "object_datafordelerRowId"
      assert_equal 2, body.dig("variables", "first")
      assert_nil body.dig("variables", "after")
      assert_equal({ "eventid" => { "gt" => 100 } }, body.dig("variables", "where"))

      ok_json(
        "data" => {
          "CVR_Events" => {
            "pageInfo" => { "hasNextPage" => false, "endCursor" => nil },
            "nodes" => []
          }
        }
      )
    end

    Cvrvaelger::Client.new(api_key: "k", http: http).events(since_event_id: 100, first: 2)
  end

  def test_events_maps_nodes_and_page_info
    http = lambda do |_uri, _request|
      ok_json(
        "data" => {
          "CVR_Events" => {
            "pageInfo" => { "hasNextPage" => true, "endCursor" => "CURSOR" },
            "nodes" => [
              {
                "eventid" => 101,
                "entityname" => "Virksomhed",
                "eventaction" => "u",
                "fromfailedimport" => false,
                "object_id" => "4000000001",
                "object_datafordelerRowId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                "datafordelerOpdateringstid" => "2026-10-09T10:00:00.000000Z",
                "datafordelerRegisterImportSequenceNumber" => 9
              }
            ]
          }
        }
      )
    end

    page = Cvrvaelger::Client.new(api_key: "k", http: http).events(since_event_id: 100, first: 2)

    assert page.has_next_page
    assert_equal "CURSOR", page.end_cursor
    assert_equal 1, page.events.size

    event = page.events.first

    assert_equal 101, event.event_id
    assert_equal "Virksomhed", event.entity_name
    assert_equal "u", event.event_action
    refute event.from_failed_import
    assert_equal "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", event.object_datafordeler_row_id
  end

  def test_events_maps_optional_event_fields
    http = lambda do |_uri, _request|
      ok_json(
        "data" => {
          "CVR_Events" => {
            "pageInfo" => { "hasNextPage" => false, "endCursor" => nil },
            "nodes" => [
              {
                "eventid" => 1,
                "entityname" => "Navn",
                "eventaction" => "i",
                "fromfailedimport" => true,
                "object_id" => "4000000001",
                "object_datafordelerRowId" => "row",
                "datafordelerOpdateringstid" => "2026-10-09T10:00:00.000000Z",
                "datafordelerRegisterImportSequenceNumber" => 9
              }
            ]
          }
        }
      )
    end

    event = Cvrvaelger::Client.new(api_key: "k", http: http).events.events.first

    assert_equal "4000000001", event.object_entity_id
    assert_equal "2026-10-09T10:00:00.000000Z", event.datafordeler_opdateringstid
    assert_equal 9, event.datafordeler_register_import_sequence_number
    assert event.from_failed_import
  end

  def test_events_uses_gte_when_inclusive
    http = lambda do |_uri, request|
      body = JSON.parse(request.body)

      assert_equal({ "eventid" => { "gte" => 50 } }, body.dig("variables", "where"))
      assert_equal "AFTER", body.dig("variables", "after")

      ok_json(
        "data" => {
          "CVR_Events" => {
            "pageInfo" => { "hasNextPage" => false, "endCursor" => nil },
            "nodes" => []
          }
        }
      )
    end

    page = Cvrvaelger::Client.new(api_key: "k", http: http).events(
      since_event_id: 50,
      inclusive: true,
      after: "AFTER",
      first: 10
    )

    refute page.has_next_page
    assert_empty page.events
  end

  def test_events_without_since_omits_event_id_filter
    http = lambda do |_uri, request|
      body = JSON.parse(request.body)
      query = body.fetch("query")

      refute_includes query, "$where"
      assert_nil body.dig("variables", "where")
      assert_equal 100, body.dig("variables", "first")

      ok_json(
        "data" => {
          "CVR_Events" => {
            "pageInfo" => { "hasNextPage" => false, "endCursor" => nil },
            "nodes" => []
          }
        }
      )
    end

    page = Cvrvaelger::Client.new(api_key: "k", http: http).events

    assert_empty page.events
  end

  def test_virksomhed_by_row_id_returns_graphql_hash
    http = lambda do |_uri, request|
      body = JSON.parse(request.body)

      assert_includes body.fetch("query"), "CVR_Virksomhed"
      assert_equal "row-1", body.dig("variables", "rowId")
      assert_equal STAMP, body.dig("variables", "at")

      ok_json(
        "data" => {
          "CVR_Virksomhed" => {
            "nodes" => [
              {
                "id" => "4000000001",
                "CVRNummer" => 25_052_943,
                "status" => "aktiv",
                "datafordelerRowId" => "row-1"
              }
            ]
          }
        }
      )
    end

    row = Cvrvaelger::Client.new(api_key: "k", http: http).virksomhed_by_row_id("row-1", at: AT)

    assert_equal "4000000001", row["id"]
    assert_equal 25_052_943, row["CVRNummer"]
    assert_equal "aktiv", row["status"]
    assert_equal "row-1", row["datafordelerRowId"]
  end

  def test_navn_and_adressering_by_row_id
    calls = []
    http = lambda do |_uri, request|
      body = JSON.parse(request.body)
      query = body.fetch("query")
      calls << query

      if query.include?("CVR_Navn")
        ok_json(
          "data" => {
            "CVR_Navn" => {
              "nodes" => [{ "CVREnhedsId" => "e1", "vaerdi" => "Example ApS", "datafordelerRowId" => "n1" }]
            }
          }
        )
      else
        ok_json(
          "data" => {
            "CVR_Adressering" => {
              "nodes" => [
                {
                  "CVREnhedsId" => "e1",
                  "AdresseringAnvendelse" => "beliggenhedsadresse",
                  "CVRAdresse_vejnavn" => "Titangade",
                  "CVRAdresse_husnummerFra" => "11",
                  "CVRAdresse_postnummer" => "2200",
                  "CVRAdresse_postdistrikt" => "København N",
                  "datafordelerRowId" => "a1"
                }
              ]
            }
          }
        )
      end
    end

    client = Cvrvaelger::Client.new(api_key: "k", http: http)
    navn = client.navn_by_row_id("n1", at: AT)
    adresse = client.adressering_by_row_id("a1", at: AT)

    assert_equal "Example ApS", navn["vaerdi"]
    assert_equal "Titangade", adresse["CVRAdresse_vejnavn"]
    assert_equal 2, calls.size
  end

  def test_entity_by_row_id_returns_nil_when_missing
    http = lambda do |_uri, _request|
      ok_json("data" => { "CVR_Virksomhed" => { "nodes" => [] } })
    end

    assert_nil Cvrvaelger::Client.new(api_key: "k", http: http).virksomhed_by_row_id("missing", at: AT)
  end

  def test_register_import_status
    http = lambda do |_uri, request|
      assert_includes JSON.parse(request.body).fetch("query"), "DAF_RegisterImportStatus"

      ok_json(
        "data" => {
          "DAF_RegisterImportStatus" => {
            "lastEventId" => 999,
            "lastSequenceNumber" => 42,
            "lastUpdated" => "2026-10-09T12:00:00.000000Z"
          }
        }
      )
    end

    status = Cvrvaelger::Client.new(api_key: "k", http: http).register_import_status

    assert_equal 999, status["lastEventId"]
    assert_equal 42, status["lastSequenceNumber"]
    assert_equal "2026-10-09T12:00:00.000000Z", status["lastUpdated"]
  end

  def test_events_requires_api_key
    previous_cvr = ENV.delete("CVRVAELGER_API_KEY")
    previous_df = ENV.delete("DATAFORDELER_API_KEY")
    error = assert_raises(Cvrvaelger::ConfigurationError) do
      Cvrvaelger::Client.new(api_key: nil, http: ->(*) { flunk "no" }).events
    end
    assert_match(/CVRVAELGER_API_KEY/, error.message)
  ensure
    ENV["CVRVAELGER_API_KEY"] = previous_cvr if previous_cvr
    ENV["DATAFORDELER_API_KEY"] = previous_df if previous_df
  end

  private

  def ok_json(payload)
    Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
      body = JSON.generate(payload)
      response.define_singleton_method(:body) { body }
      response.define_singleton_method(:[]) { |name| name.to_s.downcase == "content-type" ? "application/json" : nil }
    end
  end
end
