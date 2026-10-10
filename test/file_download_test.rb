# frozen_string_literal: true

require "test_helper"
require "json"
require "net/http"
require "tmpdir"

class FileDownloadTest < Minitest::Test
  def test_default_file_download_base_url
    assert_equal "https://api.datafordeler.dk", Cvrvaelger::Client::DEFAULT_FILE_DOWNLOAD_BASE_URL
  end

  def test_available_file_downloads_maps_metadata
    http = lambda do |uri, request|
      assert_kind_of Net::HTTP::Get, request
      assert_includes uri.to_s, "api.datafordeler.dk/FileDownloads/GetAvailableFileDownloads"
      assert_includes uri.to_s, "Register=CVR"
      assert_includes uri.to_s, "apiKey=test-key"

      ok_json(
        "paginationMetadata" => { "totalCount" => 1 },
        "availableFileDownloads" => [
          {
            "fileName" => "CVR_V2_Navn_TotalDownload_json_Current_525.zip",
            "register" => "CVR",
            "entityName" => "Navn",
            "typeOfDownload" => "TotalDownload",
            "typeOfData" => "Current",
            "containedFileFormat" => "json",
            "outputFileFormat" => "zip",
            "generationNumber" => 525,
            "fileSizeInBytes" => 267_374_119,
            "md5Hash" => "abc",
            "generationTime" => "2026-10-09T23:00:00.000000Z",
            "expirationDate" => "2026-10-16T23:00:00.000000Z"
          }
        ]
      )
    end

    files = Cvrvaelger::Client.new(api_key: "test-key", http: http).available_file_downloads

    assert_equal 1, files.size
    file = files.first

    assert_equal "CVR_V2_Navn_TotalDownload_json_Current_525.zip", file.file_name
    assert_equal "Navn", file.entity_name
    assert_equal "Current", file.type_of_data
    assert_equal "json", file.contained_file_format
    assert_equal 525, file.generation_number
    assert_equal 267_374_119, file.file_size_in_bytes
  end

  def test_available_file_downloads_can_filter_entity
    http = lambda do |_uri, _request|
      ok_json(
        "availableFileDownloads" => [
          { "fileName" => "a.zip", "entityName" => "Navn", "typeOfData" => "Current", "containedFileFormat" => "json" },
          { "fileName" => "b.zip", "entityName" => "Virksomhed", "typeOfData" => "Current",
            "containedFileFormat" => "json" }
        ]
      )
    end

    files = Cvrvaelger::Client.new(api_key: "k", http: http).available_file_downloads(entity: "Virksomhed")

    assert_equal ["b.zip"], files.map(&:file_name)
  end

  def test_download_file_writes_bytes_to_path
    http = lambda do |uri, request|
      assert_kind_of Net::HTTP::Get, request
      assert_includes uri.to_s, "GetFile"
      assert_includes uri.to_s, "Filename=CVR_V2_Navn_TotalDownload_json_Current_525.zip"
      binary("PK\x03\x04fake-zip")
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "navn.zip")
      result = Cvrvaelger::Client.new(api_key: "k", http: http).download_file(
        "CVR_V2_Navn_TotalDownload_json_Current_525.zip",
        to: path
      )

      assert_equal path, result
      assert_equal "PK\x03\x04fake-zip", File.binread(path)
    end
  end

  def test_download_latest_uses_latest_total_for_entity
    http = lambda do |uri, request|
      assert_kind_of Net::HTTP::Get, request
      assert_includes uri.query, "LatestTotalForEntity=Virksomhed"
      assert_includes uri.query, "type=current"
      assert_includes uri.query, "format=JSON"
      assert_includes uri.query, "Register=CVR"
      binary("zip-bytes")
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "virksomhed.zip")
      Cvrvaelger::Client.new(api_key: "k", http: http).download_latest(
        entity: "Virksomhed",
        type: "current",
        format: "json",
        to: path
      )

      assert_equal "zip-bytes", File.binread(path)
    end
  end

  def test_download_requires_api_key
    previous_cvr = ENV.delete("CVRVAELGER_API_KEY")
    previous_df = ENV.delete("DATAFORDELER_API_KEY")
    error = assert_raises(Cvrvaelger::ConfigurationError) do
      Cvrvaelger::Client.new(api_key: nil, http: ->(*) { flunk "no" }).available_file_downloads
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

  def binary(bytes)
    Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
      response.define_singleton_method(:body) { bytes }
      response.define_singleton_method(:[]) { |name| name.to_s.downcase == "content-type" ? "application/zip" : nil }
    end
  end
end
