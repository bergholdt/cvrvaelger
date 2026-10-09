# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  def test_version_present
    assert_match(/\A\d+\.\d+\.\d+\z/, Cvrvaelger::VERSION)
  end
end
