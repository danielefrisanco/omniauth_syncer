# frozen_string_literal: true

module FixtureHelpers
  # Fresh, deep copy of a fixture auth hash (string keys, as OmniAuth builds it).
  def auth_fixture(name)
    JSON.parse(File.read(File.join(__dir__, '..', 'fixtures', "#{name}.json")))
  end
end

RSpec.configure { |config| config.include FixtureHelpers }
