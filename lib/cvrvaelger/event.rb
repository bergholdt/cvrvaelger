# frozen_string_literal: true

module Cvrvaelger
  # One CVR_Events row from Datafordeler GraphQL (pull/poll sync cursor).
  Event = Data.define(
    :event_id,
    :entity_name,
    :event_action,
    :from_failed_import,
    :object_entity_id,
    :object_datafordeler_row_id,
    :datafordeler_opdateringstid,
    :datafordeler_register_import_sequence_number
  ) do
    def self.from_node(node)
      new(
        event_id: node["eventid"],
        entity_name: present_string(node["entityname"]),
        event_action: present_string(node["eventaction"]),
        from_failed_import: node["fromfailedimport"],
        # GraphQL field object_id — not Ruby Object#object_id.
        object_entity_id: present_string(node["object_id"]),
        object_datafordeler_row_id: present_string(node["object_datafordelerRowId"]),
        datafordeler_opdateringstid: present_string(node["datafordelerOpdateringstid"]),
        datafordeler_register_import_sequence_number: node["datafordelerRegisterImportSequenceNumber"]
      )
    end

    def self.present_string(value)
      return nil if value.nil?

      string = value.to_s.strip
      string.empty? ? nil : string
    end

    private_class_method :present_string
  end

  # One page of CVR_Events plus GraphQL connection cursors.
  EventPage = Data.define(:events, :has_next_page, :end_cursor) do
    def self.from_connection(connection)
      connection = {} unless connection.is_a?(Hash)
      page_info = connection["pageInfo"]
      page_info = {} unless page_info.is_a?(Hash)

      new(
        events: Array(connection["nodes"]).grep(Hash).map { |node| Event.from_node(node) },
        has_next_page: page_info["hasNextPage"] == true,
        end_cursor: present_string(page_info["endCursor"])
      )
    end

    def self.present_string(value)
      return nil if value.nil?

      string = value.to_s.strip
      string.empty? ? nil : string
    end

    private_class_method :present_string
  end
end
