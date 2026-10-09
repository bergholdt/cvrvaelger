# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  def test_version_present
    assert Cvrvaelger::VERSION.match?(/\A\d+\.\d+\.\d+\z/)
  end
end
