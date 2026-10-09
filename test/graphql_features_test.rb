# frozen_string_literal: true

require "test_helper"

# Recorded examples of the CVR GraphQL v2 query surface.
# CVR_CVRPerson is confidential (CPR) and is not called.
# Subscriptions are push channels and are not recorded with VCR.
class GraphqlFeaturesTest < Minitest::Test
  include LiveClient

  LEGO_ID = "4001142075"
  LEGO_CVR = 47_458_714
  SALLING_CVR = 35_954_716
  STAMP = "2026-10-09T12:00:00.000000Z"

  def test_virksomhed_eq_virkningstid_and_page_info
    with_cassette("virksomhed_eq") do
      node = nodes_for(<<~GQL, "CVR_Virksomhed").first
        {
          CVR_Virksomhed(first: 1, virkningstid: "#{STAMP}", where: { CVRNummer: { eq: #{LEGO_CVR} } }) {
            pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
            nodes { id CVRNummer status virksomhedStartdato }
          }
        }
      GQL

      assert_equal LEGO_ID, node["id"]
      assert_equal LEGO_CVR, node["CVRNummer"]
      assert_equal "aktiv", node["status"]
      assert_equal "1973-07-01", node["virksomhedStartdato"]
    end
  end

  def test_virksomhed_in_filter_returns_lego_and_salling_group
    with_cassette("virksomhed_in") do
      cvrs = nodes_for(<<~GQL, "CVR_Virksomhed").map { |node| node["CVRNummer"] }
        {
          CVR_Virksomhed(first: 5, virkningstid: "#{STAMP}", where: { CVRNummer: { in: [#{LEGO_CVR}, #{SALLING_CVR}] } }) {
            nodes { CVRNummer }
          }
        }
      GQL

      assert_includes cvrs, LEGO_CVR
      assert_includes cvrs, SALLING_CVR
    end
  end

  def test_virksomhed_and_gte_filter
    with_cassette("virksomhed_and_gte") do
      node = nodes_for(<<~GQL, "CVR_Virksomhed").first
        {
          CVR_Virksomhed(
            first: 1
            virkningstid: "#{STAMP}"
            where: { and: [{ CVRNummer: { eq: #{LEGO_CVR} } }, { virksomhedStartdato: { gte: "1973-07-01" } }] }
          ) {
            nodes { CVRNummer virksomhedStartdato }
          }
        }
      GQL

      assert_equal LEGO_CVR, node["CVRNummer"]
    end
  end

  def test_virksomhed_unknown_cvr_is_empty
    with_cassette("virksomhed_unknown") do
      assert_empty nodes_for(<<~GQL, "CVR_Virksomhed")
        {
          CVR_Virksomhed(first: 1, virkningstid: "#{STAMP}", where: { CVRNummer: { eq: 0 } }) {
            nodes { id }
          }
        }
      GQL
    end
  end

  def test_navn_exact_match_and_string_in_filter
    with_cassette("navn_eq_and_in") do
      exact = nodes_for(<<~GQL, "CVR_Navn")
        {
          CVR_Navn(first: 5, virkningstid: "#{STAMP}", where: { vaerdi: { eq: "LEGO SYSTEM A/S" } }) {
            nodes { CVREnhedsId vaerdi }
          }
        }
      GQL
      assert_includes exact.map { |node| node["CVREnhedsId"] }, LEGO_ID

      listed = nodes_for(<<~GQL, "CVR_Navn").map { |node| node["vaerdi"] }
        {
          CVR_Navn(first: 10, virkningstid: "#{STAMP}", where: { vaerdi: { in: ["LEGO SYSTEM A/S", "Salling Group A/S"] } }) {
            nodes { vaerdi }
          }
        }
      GQL
      assert_includes listed, "LEGO SYSTEM A/S"
      assert_includes listed, "Salling Group A/S"
    end
  end

  def test_navn_fragments_and_unknown_name_are_empty
    {
      "navn_fragment_lego" => "lego",
      "navn_fragment_salling_group" => "salling group",
      "navn_wrong_case" => "SALLING GROUP A/S",
      "navn_unknown" => "ZZZ-FINDES-IKKE-APS"
    }.each do |cassette, name|
      with_cassette(cassette) do
        assert_empty nodes_for(<<~GQL, "CVR_Navn"), name
          {
            CVR_Navn(first: 5, virkningstid: "#{STAMP}", where: { vaerdi: { eq: "#{name}" } }) {
              nodes { vaerdi }
            }
          }
        GQL
      end
    end
  end

  def test_navn_pagination_after_cursor
    with_cassette("navn_pagination") do
      first = connection(<<~GQL, "CVR_Navn")
        {
          CVR_Navn(first: 1, where: { vaerdi: { eq: "LEGO SYSTEM A/S" } }) {
            pageInfo { hasNextPage endCursor }
            nodes { CVREnhedsId }
          }
        }
      GQL
      assert first.dig("pageInfo", "hasNextPage")
      cursor = first.dig("pageInfo", "endCursor")

      refute_nil cursor

      second = connection(<<~GQL, "CVR_Navn", after: cursor)
        query($after: String!) {
          CVR_Navn(first: 1, after: $after, where: { vaerdi: { eq: "LEGO SYSTEM A/S" } }) {
            pageInfo { hasPreviousPage }
            nodes { CVREnhedsId }
          }
        }
      GQL

      # `after` returns the next row. Datafordeler leaves hasPreviousPage false.
      refute_equal first.dig("nodes", 0, "CVREnhedsId"), second.dig("nodes", 0, "CVREnhedsId")
    end
  end

  def test_navn_without_required_filter_is_rejected
    with_cassette("navn_missing_filter") do
      error = assert_raises(Cvrvaelger::ProviderError) do
        graphql("{ CVR_Navn(first: 1) { nodes { vaerdi } } }")
      end
      assert_match(/GraphQL error/, error.message)
    end
  end

  def test_related_entities_for_lego
    {
      "CVR_Adressering" => "CVRAdresse_vejnavn",
      "CVR_Branche" => "vaerdi vaerdiTekst",
      "CVR_Telefonnummer" => "vaerdi",
      "CVR_e_mailadresse" => "vaerdi",
      "CVR_Reklamebeskyttelse" => "vaerdi",
      "CVR_Kreditoplysninger" => "Kreditoplysning kreditoplysningstekst statusvaerdi",
      "CVR_AnsvarligDataleverandoer" => "vaerdi vaerdiTekst",
      "CVR_FuldtAnsvarligDeltagerRelation" => "deltagendeEnhedsId",
      "CVR_Virksomhedsform" => "vaerdi vaerdiTekst"
    }.each do |field, selection|
      with_cassette("entity_#{field}") do
        connection = connection(<<~GQL, field)
          {
            #{field}(first: 1, virkningstid: "#{STAMP}", where: { CVREnhedsId: { eq: "#{LEGO_ID}" } }) {
              pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
              nodes { #{selection} }
            }
          }
        GQL

        assert_kind_of Array, connection["nodes"], field
        assert connection["pageInfo"].key?("hasNextPage"), "missing hasNextPage for #{field}"
      end
    end
  end

  def test_beskaeftigelse_has_no_virkningstid_argument
    with_cassette("entity_CVR_Beskaeftigelse") do
      rows = nodes_for(<<~GQL, "CVR_Beskaeftigelse")
        {
          CVR_Beskaeftigelse(first: 1, where: { CVREnhedsId: { eq: "#{LEGO_ID}" } }) {
            pageInfo { hasNextPage }
            nodes { antal intervalFra intervalTil beskaeftigelsestalstype }
          }
        }
      GQL

      assert_kind_of Array, rows
    end
  end

  def test_cvr_enhed_by_id
    with_cassette("entity_CVR_CVREnhed") do
      node = nodes_for(<<~GQL, "CVR_CVREnhed").first
        {
          CVR_CVREnhed(first: 1, where: { id: { eq: "#{LEGO_ID}" } }) {
            nodes { id enhedsType forretningsnoegle forretningsnoegletype status }
          }
        }
      GQL

      assert_equal LEGO_ID, node["id"]
      refute_nil node["enhedsType"]
      refute_nil node["forretningsnoegle"]
    end
  end

  def test_produktionsenhed_by_cvr_nummer
    with_cassette("entity_CVR_Produktionsenhed") do
      rows = nodes_for(<<~GQL, "CVR_Produktionsenhed")
        {
          CVR_Produktionsenhed(first: 1, virkningstid: "#{STAMP}", where: { tilknyttetVirksomhedsCVRNummer: { eq: #{LEGO_CVR} } }) {
            pageInfo { hasNextPage }
            nodes { id pNummer status }
          }
        }
      GQL

      assert_kind_of Array, rows
      refute_empty rows
      refute_nil rows.first["pNummer"]
    end
  end

  def test_andre_deltagere_unknown_id_is_empty
    with_cassette("entity_CVR_AndreDeltagere_empty") do
      assert_empty nodes_for(<<~GQL, "CVR_AndreDeltagere")
        {
          CVR_AndreDeltagere(first: 1, virkningstid: "#{STAMP}", where: { id: { eq: "0000000000" } }) {
            nodes { id status type }
          }
        }
      GQL
    end
  end

  def test_telefaxnummer_unknown_row_is_empty
    with_cassette("entity_CVR_Telefaxnummer_empty") do
      assert_empty nodes_for(<<~GQL, "CVR_Telefaxnummer")
        {
          CVR_Telefaxnummer(first: 1, virkningstid: "#{STAMP}", where: { datafordelerRowId: { eq: "00000000-0000-0000-0000-000000000000" } }) {
            nodes { vaerdi }
          }
        }
      GQL
    end
  end

  def test_events_first_and_after
    with_cassette("entity_CVR_Events") do
      first = connection(<<~GQL, "CVR_Events")
        {
          CVR_Events(first: 1) {
            pageInfo { hasNextPage endCursor }
            nodes { eventid entityname eventaction }
          }
        }
      GQL
      refute_empty first["nodes"]
      assert first["nodes"].first["eventid"]

      if first.dig("pageInfo", "hasNextPage")
        second = connection(<<~GQL, "CVR_Events", after: first.dig("pageInfo", "endCursor"))
          query($after: String!) {
            CVR_Events(first: 1, after: $after) {
              nodes { eventid }
            }
          }
        GQL
        refute_equal first.dig("nodes", 0, "eventid"), second.dig("nodes", 0, "eventid")
      end
    end
  end

  def test_register_import_status
    with_cassette("daf_register_import_status") do
      status = graphql("{ DAF_RegisterImportStatus { lastEventId lastSequenceNumber lastUpdated } }")
      row = status.dig("data", "DAF_RegisterImportStatus")

      assert_kind_of Integer, row["lastSequenceNumber"]
      refute_nil row["lastEventId"]
      refute_nil row["lastUpdated"]
    end
  end

  private

  def with_cassette(name, &)
    VCR.use_cassette(name, &)
  end

  def nodes_for(query, field, **variables)
    connection(query, field, **variables).fetch("nodes")
  end

  def connection(query, field, **variables)
    graphql(query, **variables).dig("data", field)
  end

  def graphql(query, **variables)
    live_client.send(:post_graphql, query, **variables)
  end
end
