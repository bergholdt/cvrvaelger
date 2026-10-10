# frozen_string_literal: true

require "test_helper"

class ClientEventsLiveTest < Minitest::Test
  include LiveClient

  def test_events_page_and_since_cursor
    VCR.use_cassette("client_events_page") do
      page = live_client.events(first: 2)

      refute_empty page.events
      first = page.events.first

      assert_kind_of Integer, first.event_id
      refute_nil first.entity_name
      assert_includes %w[i u d], first.event_action
      refute_nil first.object_datafordeler_row_id

      since = live_client.events(since_event_id: first.event_id, first: 1)

      refute_empty since.events
      assert_operator since.events.first.event_id, :>, first.event_id
    end
  end

  def test_events_pagination_after_cursor
    VCR.use_cassette("client_events_after") do
      first = live_client.events(first: 1)
      skip "no next page" unless first.has_next_page && first.end_cursor

      second = live_client.events(first: 1, after: first.end_cursor)

      refute_empty second.events
      refute_equal first.events.first.event_id, second.events.first.event_id
    end
  end

  def test_register_import_status
    VCR.use_cassette("client_register_import_status") do
      status = live_client.register_import_status

      assert_kind_of Integer, status["lastSequenceNumber"]
      refute_nil status["lastEventId"]
      refute_nil status["lastUpdated"]
    end
  end

  def test_entity_by_row_id_from_event
    VCR.use_cassette("client_events_entity_by_row_id") do
      page = live_client.events(first: 50)
      event = page.events.find { |row| %w[Virksomhed Navn Adressering].include?(row.entity_name) }
      skip "no Virksomhed/Navn/Adressering event in first page" unless event

      row =
        case event.entity_name
        when "Virksomhed"
          live_client.virksomhed_by_row_id(event.object_datafordeler_row_id, at: AT)
        when "Navn"
          live_client.navn_by_row_id(event.object_datafordeler_row_id, at: AT)
        when "Adressering"
          live_client.adressering_by_row_id(event.object_datafordeler_row_id, at: AT)
        end

      # Deletes may leave no current row at virkningstid; still assert a typed call succeeded.
      assert(row.nil? || row.is_a?(Hash))
      assert_equal event.object_datafordeler_row_id, row["datafordelerRowId"] if row
    end
  end
end
