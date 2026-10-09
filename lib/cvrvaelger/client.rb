# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

require_relative "company"

module Cvrvaelger
  # HTTP client for Det Centrale Virksomhedsregister via Datafordeler GraphQL.
  #
  # Official endpoint: https://graphql.datafordeler.dk/CVR/v1
  # Auth: free API key from Datafordeler Administration (query param `apiKey`).
  # No demo/default secret — configure CVRVAELGER_API_KEY or pass api_key:.
  class Client
    DEFAULT_BASE_URL = "https://graphql.datafordeler.dk/CVR/v1"

    # Minimal company lookup. Field shapes follow Datafordeler CVR GraphQL
    # community examples (CVREnhed); parsing tolerates nested/flat navn.
    LOOKUP_QUERY = <<~GRAPHQL.freeze
      query LookupCvr($cvr: String!) {
        CVREnhed(where: { cvrNummer: { eq: $cvr } }) {
          nodes {
            cvrNummer
            navn
            adresse {
              vejnavn
              husnummer
              postnummer
              postdistrikt
            }
          }
        }
      }
    GRAPHQL

    SEARCH_QUERY = <<~GRAPHQL.freeze
      query SearchCvr($q: String!) {
        CVREnhed(where: { navn: { contains: $q } }, first: 10) {
          nodes {
            cvrNummer
            navn
            adresse {
              vejnavn
              husnummer
              postnummer
              postdistrikt
            }
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
    def lookup(cvr)
      normalized = Company.normalize_cvr(cvr)
      return nil unless present?(normalized)

      ensure_api_key!
      payload = post_graphql(LOOKUP_QUERY, cvr: normalized)
      node = first_node(payload)
      return nil unless present?(node)

      company = Company.from_node(node)
      return nil unless present?(company.cvr) && present?(company.name)

      company
    end

    # Picker search: 8-digit query → single lookup; otherwise name contains search.
    def search(query)
      q = query.to_s.strip
      return [] if q.length < 2

      digits = Company.normalize_cvr(q)
      if digits
        company = lookup(digits)
        return company ? [ company ] : []
      end

      ensure_api_key!
      payload = post_graphql(SEARCH_QUERY, q: q)
      Array(nodes(payload)).filter_map do |node|
        company = Company.from_node(node)
        next unless present?(company.cvr) && present?(company.name)

        company
      end
    end

    private

      attr_reader :http

      def ensure_api_key!
        return if present?(api_key)

        raise ConfigurationError,
          "CVRVAELGER_API_KEY (or DATAFORDELER_API_KEY) is required — create a free API key in Datafordeler Administration"
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

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |client|
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
