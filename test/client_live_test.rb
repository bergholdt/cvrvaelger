# frozen_string_literal: true

require "test_helper"

class ClientLiveTest < Minitest::Test
  include LiveClient

  def test_lookup_lego
    VCR.use_cassette("lookup_lego") do
      company = live_client.lookup("47458714", at: AT)

      assert_equal "47458714", company.cvr
      assert_equal "LEGO SYSTEM A/S", company.name
      assert_equal "Åstvej 1", company.address_line
      assert_equal "7190", company.postal_code
      assert_equal "Billund", company.city
      assert_equal "aktiv", company.status
      assert_equal "datafordeler_cvr", company.provider
    end
  end

  def test_lookup_salling_group
    VCR.use_cassette("lookup_salling_group") do
      company = live_client.lookup("35954716", at: AT)

      assert_equal "35954716", company.cvr
      assert_equal "Salling Group A/S", company.name
      assert_equal "Rosbjergvej 33", company.address_line
      assert_equal "8220", company.postal_code
      assert_equal "Brabrand", company.city
      assert_equal "aktiv", company.status
    end
  end

  def test_lookup_unknown_cvr_returns_nil
    VCR.use_cassette("lookup_unknown_cvr") do
      assert_nil live_client.lookup("00000000", at: AT)
    end
  end

  def test_search_lego_by_registered_name
    VCR.use_cassette("search_lego_name") do
      hits = live_client.search("LEGO SYSTEM A/S", at: AT)

      assert_includes hits.map(&:cvr), "47458714"
      assert_includes hits.map(&:name), "LEGO SYSTEM A/S"
    end
  end

  def test_search_salling_group_by_registered_name
    VCR.use_cassette("search_salling_group_name") do
      hits = live_client.search("Salling Group A/S", at: AT)

      assert_includes hits.map(&:cvr), "35954716"
      assert_includes hits.map(&:name), "Salling Group A/S"
    end
  end

  def test_search_lego_fragment_finds_nothing
    VCR.use_cassette("search_lego_fragment") do
      assert_empty live_client.search("lego", at: AT)
    end
  end

  def test_search_salling_group_fragment_finds_nothing
    VCR.use_cassette("search_salling_group_fragment") do
      assert_empty live_client.search("salling group", at: AT)
    end
  end

  def test_search_wrong_case_finds_nothing
    VCR.use_cassette("search_salling_group_wrong_case") do
      assert_empty live_client.search("SALLING GROUP A/S", at: AT)
    end
  end

  def test_search_unknown_name_finds_nothing
    VCR.use_cassette("search_unknown_name") do
      assert_empty live_client.search("ZZZ-FINDES-IKKE-APS", at: AT)
    end
  end
end
