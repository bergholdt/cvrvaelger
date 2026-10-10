# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

require_relative "company"
require_relative "file_download"
require_relative "event"
require_relative "client_events"

module Cvrvaelger
  # HTTP client for Det Centrale Virksomhedsregister via Datafordeler GraphQL
  # and Fildownload.
  #
  # GraphQL: https://graphql.datafordeler.dk/CVR/v2
  # Files:   https://api.datafordeler.dk/FileDownloads/...
  # Auth: free API key from Datafordeler Administration (query param `apiKey`).
  # No demo/default secret — configure CVRVAELGER_API_KEY or pass api_key:.
  #
  class Client
    include ClientEvents

    DEFAULT_BASE_URL = "https://graphql.datafordeler.dk/CVR/v2"
    DEFAULT_FILE_DOWNLOAD_BASE_URL = "https://api.datafordeler.dk"

    # Datafordeler allows one root field per query. Name match is exact (`eq`);
    # there is no contains/fuzzy operator. `virkningstid` selects the bitemporal row.
    VIRKSOMHED_BY_CVR_QUERY = <<~GRAPHQL
      query LookupVirksomhed($cvr: Long!, $at: DafDateTime!) {
        CVR_Virksomhed(first: 1, virkningstid: $at, where: { CVRNummer: { eq: $cvr } }) {
          nodes { id CVRNummer status }
        }
      }
    GRAPHQL

    VIRKSOMHED_BY_ID_QUERY = <<~GRAPHQL
      query VirksomhedById($id: String!, $at: DafDateTime!) {
        CVR_Virksomhed(first: 1, virkningstid: $at, where: { id: { eq: $id } }) {
          nodes { id CVRNummer status }
        }
      }
    GRAPHQL

    NAVN_BY_ID_QUERY = <<~GRAPHQL
      query NavnById($id: String!, $at: DafDateTime!) {
        CVR_Navn(first: 1, virkningstid: $at, where: { CVREnhedsId: { eq: $id } }) {
          nodes { vaerdi }
        }
      }
    GRAPHQL

    NAVN_BY_VALUE_QUERY = <<~GRAPHQL
      query SearchNavn($q: String!, $at: DafDateTime!) {
        CVR_Navn(first: 10, virkningstid: $at, where: { vaerdi: { eq: $q } }) {
          nodes { CVREnhedsId vaerdi }
        }
      }
    GRAPHQL

    ADRESSE_BY_ID_QUERY = <<~GRAPHQL
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

    attr_reader :base_url, :file_download_base_url, :api_key

    def initialize(api_key: nil, base_url: nil, file_download_base_url: nil, http: nil)
      @api_key = present_string(api_key) || present_string(ENV.fetch("CVRVAELGER_API_KEY", nil)) ||
                 present_string(ENV.fetch("DATAFORDELER_API_KEY", nil))
      @base_url = present_string(base_url) || present_string(ENV.fetch("CVRVAELGER_BASE_URL", nil)) || DEFAULT_BASE_URL
      @file_download_base_url = present_string(file_download_base_url) ||
                                present_string(ENV.fetch("CVRVAELGER_FILE_DOWNLOAD_BASE_URL", nil)) ||
                                DEFAULT_FILE_DOWNLOAD_BASE_URL
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
        return company ? [company] : []
      end

      ensure_api_key!
      stamp = format_time(at)
      payload = post_graphql(NAVN_BY_VALUE_QUERY, q: q, at: stamp)
      Array(nodes(payload)).filter_map { |node| node["CVREnhedsId"] }.uniq.filter_map do |id|
        company_from_id(id, stamp)
      end
    end

    # List available CVR totaldownload zips (metadata only).
    # Optional filters: entity ("Navn"), type_of_data ("Current"), format ("json").
    def available_file_downloads(entity: nil, type_of_data: nil, format: nil)
      ensure_api_key!
      payload = get_json("/FileDownloads/GetAvailableFileDownloads", Register: "CVR")
      rows = Array(payload["availableFileDownloads"])
      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        file = FileDownload.from_node(row)
        next if entity && !entity.to_s.casecmp?(file.entity_name.to_s)
        next if type_of_data && !type_of_data.to_s.casecmp?(file.type_of_data.to_s)
        next if format && !format.to_s.casecmp?(file.contained_file_format.to_s)

        file
      end
    end

    # Download a named zip to `to` (filesystem path). Returns the path.
    def download_file(file_name, to:)
      ensure_api_key!
      raise ArgumentError, "to: path is required" if blank?(to)
      raise ArgumentError, "file_name is required" if blank?(file_name)

      get_file({ Filename: file_name.to_s }, to: to.to_s)
    end

    # Download the latest totaldownload for an entity (e.g. Navn / Virksomhed).
    # `type` is Current/Temporal/Bitemporal; `format` is json/csv.
    def download_latest(entity:, to:, type: "current", format: "json")
      ensure_api_key!
      raise ArgumentError, "entity is required" if blank?(entity)
      raise ArgumentError, "to: path is required" if blank?(to)

      get_file(
        {
          Register: "CVR",
          LatestTotalForEntity: entity.to_s,
          type: type.to_s.downcase,
          format: format.to_s.upcase
        },
        to: to.to_s
      )
    end

    private

    attr_reader :http

    def ensure_api_key!
      return if present?(api_key)

      raise ConfigurationError,
            "CVRVAELGER_API_KEY (or DATAFORDELER_API_KEY) is required — " \
            "create a free API key in Datafordeler Administration"
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
      rows = Array(list).grep(Hash)
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

      Array(connection["nodes"] || connection["items"] || connection["edges"]&.filter_map do |e|
        e.is_a?(Hash) ? e["node"] : nil
      end)
    end

    def post_graphql(query, **variables)
      uri = with_api_key(URI(base_url))

      body = JSON.generate(query: query, variables: variables)
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["User-Agent"] = "Cvrvaelger/#{VERSION}"
      request.body = body

      response = perform(uri, request)
      raise ProviderError, "Datafordeler CVR error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

      begin
        payload = JSON.parse(response.body)
      rescue JSON::ParserError
        raise ProviderError, "Datafordeler CVR returned invalid JSON"
      end

      if payload["errors"].is_a?(Array) && payload["errors"].any?
        message = payload["errors"].map { |err| err.is_a?(Hash) ? err["message"] : err }.compact.first
        raise ProviderError, "Datafordeler CVR GraphQL error (#{message || 'unknown'})"
      end

      payload
    end

    def get_json(path, **params)
      uri = with_api_key(URI.join("#{file_download_base_url}/", path.delete_prefix("/")), **params)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "Cvrvaelger/#{VERSION}"

      response = perform(uri, request)
      raise ProviderError, "Datafordeler CVR error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

      begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        raise ProviderError, "Datafordeler CVR returned invalid JSON"
      end
    end

    def get_file(params, to:)
      uri = with_api_key(URI.join("#{file_download_base_url}/", "FileDownloads/GetFile"), **params)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/zip, application/octet-stream, */*"
      request["User-Agent"] = "Cvrvaelger/#{VERSION}"

      if http
        response = http.call(uri, request)
        raise ProviderError, "Datafordeler CVR error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(to, response.body)
        return to
      end

      File.open(to, "wb") do |io|
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10,
                                            read_timeout: 600) do |client|
          client.request(request) do |response|
            raise ProviderError, "Datafordeler CVR error (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

            response.read_body { |chunk| io.write(chunk) }
          end
        end
      end
      to
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
      raise ProviderError, "Datafordeler CVR unreachable (#{e.class})"
    end

    def with_api_key(uri, **params)
      query_params = URI.decode_www_form(uri.query.to_s).to_h
      params.each { |key, value| query_params[key.to_s] = value unless value.nil? }
      query_params["apiKey"] = api_key
      uri.query = URI.encode_www_form(query_params)
      uri
    end

    def perform(uri, request)
      return http.call(uri, request) if http

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10,
                                          read_timeout: 30) do |client|
        client.request(request)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
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
