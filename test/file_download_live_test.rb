# frozen_string_literal: true

require "test_helper"

class FileDownloadLiveTest < Minitest::Test
  include LiveClient

  def test_lists_available_cvr_downloads
    VCR.use_cassette("fildownload_available") do
      files = live_client.available_file_downloads(entity: "Virksomhed", type_of_data: "Current", format: "json")

      refute_empty files
      assert(files.all? { |file| file.entity_name == "Virksomhed" })
      assert(files.all? { |file| file.type_of_data == "Current" })
      assert(files.all? { |file| file.contained_file_format == "json" })
      assert files.first.file_name.end_with?(".zip")
    end
  end
end
