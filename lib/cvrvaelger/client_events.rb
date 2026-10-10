# frozen_string_literal: true

module Cvrvaelger
  # Pull/poll helpers for CVR_Events and row-id entity fetch (incremental sync).
  module ClientEvents
    EVENT_NODE_FIELDS = <<~GRAPHQL
      eventid
      entityname
      eventaction
      fromfailedimport
      object_id
      object_datafordelerRowId
      datafordelerOpdateringstid
      datafordelerRegisterImportSequenceNumber
    GRAPHQL

    EVENTS_QUERY = <<~GRAPHQL.freeze
      query Events($first: Int!, $after: String) {
        CVR_Events(first: $first, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes {
            #{EVENT_NODE_FIELDS}
          }
        }
      }
    GRAPHQL

    EVENTS_SINCE_QUERY = <<~GRAPHQL.freeze
      query EventsSince($first: Int!, $after: String, $where: CVR_EventsFilterInput) {
        CVR_Events(first: $first, after: $after, where: $where) {
          pageInfo { hasNextPage endCursor }
          nodes {
            #{EVENT_NODE_FIELDS}
          }
        }
      }
    GRAPHQL

    VIRKSOMHED_BY_ROW_ID_QUERY = <<~GRAPHQL
      query VirksomhedByRowId($rowId: UUID!, $at: DafDateTime!) {
        CVR_Virksomhed(first: 1, virkningstid: $at, where: { datafordelerRowId: { eq: $rowId } }) {
          nodes { id CVRNummer status datafordelerRowId }
        }
      }
    GRAPHQL

    NAVN_BY_ROW_ID_QUERY = <<~GRAPHQL
      query NavnByRowId($rowId: UUID!, $at: DafDateTime!) {
        CVR_Navn(first: 1, virkningstid: $at, where: { datafordelerRowId: { eq: $rowId } }) {
          nodes { CVREnhedsId vaerdi datafordelerRowId }
        }
      }
    GRAPHQL

    ADRESSERING_BY_ROW_ID_QUERY = <<~GRAPHQL
      query AdresseringByRowId($rowId: UUID!, $at: DafDateTime!) {
        CVR_Adressering(first: 1, virkningstid: $at, where: { datafordelerRowId: { eq: $rowId } }) {
          nodes {
            CVREnhedsId
            AdresseringAnvendelse
            CVRAdresse_vejnavn
            CVRAdresse_husnummerFra
            CVRAdresse_postnummer
            CVRAdresse_postdistrikt
            datafordelerRowId
          }
        }
      }
    GRAPHQL

    REGISTER_IMPORT_STATUS_QUERY = <<~GRAPHQL
      query RegisterImportStatus {
        DAF_RegisterImportStatus { lastEventId lastSequenceNumber lastUpdated }
      }
    GRAPHQL

    # Page CVR_Events since a durable cursor (`eventid`).
    # `since_event_id:` uses `gt` (exclusive); `inclusive: true` uses `gte`.
    def events(since_event_id: nil, first: 100, after: nil, inclusive: false)
      ensure_api_key!
      variables = { first: first.to_i, after: after }
      if since_event_id
        op = inclusive ? "gte" : "gt"
        variables[:where] = { "eventid" => { op => since_event_id.to_i } }
        payload = post_graphql(EVENTS_SINCE_QUERY, **variables)
      else
        payload = post_graphql(EVENTS_QUERY, **variables)
      end

      EventPage.from_connection(payload.dig("data", "CVR_Events"))
    end

    # Fetch a Virksomhed GraphQL node by datafordelerRowId, or nil.
    def virksomhed_by_row_id(row_id, at: Time.now)
      entity_by_row_id(VIRKSOMHED_BY_ROW_ID_QUERY, row_id, at: at)
    end

    # Fetch a Navn GraphQL node by datafordelerRowId, or nil.
    def navn_by_row_id(row_id, at: Time.now)
      entity_by_row_id(NAVN_BY_ROW_ID_QUERY, row_id, at: at)
    end

    # Fetch an Adressering GraphQL node by datafordelerRowId, or nil.
    def adressering_by_row_id(row_id, at: Time.now)
      entity_by_row_id(ADRESSERING_BY_ROW_ID_QUERY, row_id, at: at)
    end

    # Latest import watermark from Datafordeler (bootstrap / catch-up).
    def register_import_status
      ensure_api_key!
      payload = post_graphql(REGISTER_IMPORT_STATUS_QUERY)
      status = payload.dig("data", "DAF_RegisterImportStatus")
      status.is_a?(Hash) ? status : {}
    end

    private

    def entity_by_row_id(query, row_id, at:)
      ensure_api_key!
      raise ArgumentError, "row_id is required" if blank?(row_id)

      payload = post_graphql(query, rowId: row_id.to_s, at: format_time(at))
      node = first_node(payload)
      node.is_a?(Hash) ? node : nil
    end
  end
end
