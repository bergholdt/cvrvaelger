# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

require_relative "company"

module Cvrvaelger
  # HTTP client for Det Centrale Virksomhedsregister via Datafordeler GraphQL.
  #
  # Official endpoint: https://graphql.datafordeler.dk/CVR/v2
  # Auth: free API key from Datafordeler Administration (query param `apiKey`).
  # No demo/default secret — configure CVRVAELGER_API_KEY or pass api_key:.
  class Client
    DEFAULT_BASE_URL = "https://graphql.datafordeler.dk/CVR/v2"

    # Datafordeler allows one root field per query. Name match is exact (`eq`);
    # there is no contains/fuzzy operator. `virkningstid` selects the bitemporal row.
    VIRKSOMHED_BY_CVR_QUERY = <<~GRAPHQL.freeze
      query LookupVirksomhed($cvr: Long!, $at: DafDateTime!) {
        CVR_Virksomhed(first: 1, virkningstid: $at, where: { CVRNummer: { eq: $cvr } }) {
          nodes { id CVRNummer status }
        }
      }
    GRAPHQL

    VIRKSOMHED_BY_ID_QUERY = <<~GRAPHQL.freeze
      query VirksomhedById($id: String!, $at: DafDateTime!) {
        CVR_Virksomhed(first: 1, virkningstid: $at, where: { id: { eq: $id } }) {
          nodes { id CVRNummer status }
        }
      }
    GRAPHQL

    NAVN_BY_ID_QUERY = <<~GRAPHQL.freeze
      query NavnById($id: String!, $at: DafDateTime!) {
        CVR_Navn(first: 1, virkningstid: $at, where: { CVREnhedsId: { eq: $id } }) {
          nodes { vaerdi }
        }
      }
    GRAPHQL

    NAVN_BY_VALUE_QUERY = <<~GRAPHQL.freeze
      query SearchNavn($q: String!, $at: DafDateTime!) {
        CVR_Navn(first: 10, virkningstid: $at, where: { vaerdi: { eq: $q } }) {
          nodes { CVREnhedsId vaerdi }
        }
      }
    GRAPHQL

    ADRESSE_BY_ID_QUERY = <<~GRAPHQL.freeze
      query AdresseById($id: String!, $at: DafDateTime!) {
        CVR_Adressering(first: 5, virkningstid: $at, where: { CVREnhedsId: { eq: $id } }) {
          nodes {
            AdresseringAnvendelse
            CVRAdresse_vejnavn
            CVRAdresse_husnummerFra
            CVRAdresse_postnummer
            CVRAdresse_postdistrikt
          }
        }
      }
    GRAPHQL

    attr_reader :base_url, :api_key

    def initialize(api_key: nil, base_url: nil, http: nil)
      @api_key = present_string(api_key) || present_string(ENV["CVRVAELGER_API_KEY"]) ||
        present_string(ENV["DATAFORDELER_API_KEY"])
      @base_url = present_string(base_url) || present_string(ENV["CVRVAELGER_BASE_URL"]) || DEFAULT_BASE_URL
      @http = http
    end

    # Verify an 8-digit CVR and return Company, or nil when not found.
    # `at` is the bitemporal virkningstid (default: now).
    def lookup(cvr, at: Time.now)
      normalized = Company.normalize_cvr(cvr)
      return nil unless present?(normalized)

      ensure_api_key!
      stamp = format_time(at)
      payload = post_graphql(VIRKSOMHED_BY_CVR_QUERY, cvr: normalized.to_i, at: stamp)
      node = first_node(payload)
      return nil unless present?(node)

      company_from_virksomhed(node, stamp)
    end

    # Picker search: 8 digits → lookup; otherwise exact, case-sensitive name match.
    def search(query, at: Time.now)
      q = query.to_s.strip
      return [] if q.length < 2

      digits = Company.normalize_cvr(q)
      if digits
        company = lookup(digits, at: at)
        return company ? [ company ] : []
      end

      ensure_api_key!
      stamp = format_time(at)
      payload = post_graphql(NAVN_BY_VALUE_QUERY, q: q, at: stamp)
      Array(nodes(payload)).filter_map { |node| node["CVREnhedsId"] }.uniq.filter_map do |id|
        company_from_id(id, stamp)
      end
    end

    private

      attr_reader :http

      def ensure_api_key!
        return if present?(api_key)

        raise ConfigurationError,
          "CVRVAELGER_API_KEY (or DATAFORDELER_API_KEY) is required — create a free API key in Datafordeler Administration"
      end

      def company_from_id(id, stamp)
        payload = post_graphql(VIRKSOMHED_BY_ID_QUERY, id: id, at: stamp)
        node = first_node(payload)
        return nil unless present?(node)

        company_from_virksomhed(node, stamp)
      end

      def company_from_virksomhed(node, stamp)
        id = node["id"]
        return nil unless present?(id)

        name = first_node(post_graphql(NAVN_BY_ID_QUERY, id: id, at: stamp))&.dig("vaerdi")
        address = preferred_address(nodes(post_graphql(ADRESSE_BY_ID_QUERY, id: id, at: stamp)))
        company = Company.from_node(
          "cvrNummer" => format("%08d", node["CVRNummer"].to_i),
          "navn" => name,
          "status" => node["status"],
          "adresse" => address_fields(address)
        )
        return nil unless present?(company.cvr) && present?(company.name)

        company
      end

      def preferred_address(list)
        rows = Array(list).select { |row| row.is_a?(Hash) }
        rows.find { |row| row["AdresseringAnvendelse"] == "beliggenhedsadresse" } || rows.first
      end

      def address_fields(address)
        return {} unless address.is_a?(Hash)

        {
          "vejnavn" => address["CVRAdresse_vejnavn"],
          "husnummer" => address["CVRAdresse_husnummerFra"],
          "postnummer" => address["CVRAdresse_postnummer"],
          "postdistrikt" => address["CVRAdresse_postdistrikt"]
        }
      end

      def format_time(time)
        time.getutc.strftime("%Y-%m-%dT%H:%M:%S.000000Z")
      end

      def first_node(payload)
        nodes(payload).first
      end

      def nodes(payload)
        data = payload["data"]
        return [] unless data.is_a?(Hash)

        connection = data["CVREnhed"] || data["CVR_Virksomhed"] || data["Virksomhed"] || data.values.first
        return [] unless connection.is_a?(Hash)

        Array(connection["nodes"] || connection["items"] || connection["edges"]&.filter_map { |e| e.is_a?(Hash) ? e["node"] : nil })
      end

      def post_graphql(query, **variables)
        uri = URI(base_url)
        query_params = URI.decode_www_form(uri.query.to_s).to_h
        query_params["apiKey"] = api_key
        uri.query = URI.encode_www_form(query_params)

        body = JSON.generate(query: query, variables: variables)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Cvrvaelger/#{VERSION}"
        request.body = body

        response = perform(uri, request)
        unless response.is_a?(Net::HTTPSuccess)
          raise ProviderError, "Datafordeler CVR error (#{response.code})"
        end

        payload = JSON.parse(response.body)
        if payload["errors"].is_a?(Array) && payload["errors"].any?
          message = payload["errors"].map { |err| err.is_a?(Hash) ? err["message"] : err }.compact.first
          raise ProviderError, "Datafordeler CVR GraphQL error (#{message || "unknown"})"
        end

        payload
      rescue JSON::ParserError
        raise ProviderError, "Datafordeler CVR returned invalid JSON"
      end

      def perform(uri, request)
        if http
          return http.call(uri, request)
        end

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |client|
          client.request(request)
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, Socket::ResolutionError => e
        raise ProviderError, "Datafordeler CVR unreachable (#{e.class})"
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?) ||
          (value.is_a?(String) && value.strip.empty?)
      end

      def present?(value)
        !blank?(value)
      end

      def present_string(value)
        return nil if blank?(value)

        value.to_s
      end
  end
end
