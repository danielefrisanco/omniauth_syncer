# frozen_string_literal: true

require 'json'
require 'omniauth'
require 'omniauth_syncer'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    OmniauthSyncer.reset_configuration!
  end
end
