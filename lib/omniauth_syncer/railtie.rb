# frozen_string_literal: true

module OmniauthSyncer
  # A Railtie rather than an Engine: an Engine would add this gem's app/ and
  # config/ directories to the host application.
  class Railtie < ::Rails::Railtie
    # after_initialize runs after the host's config/initializers, so the flag
    # set there is visible.
    config.after_initialize do
      next unless OmniauthSyncer.configuration.include_controller_helpers

      ActiveSupport.on_load(:action_controller_base) { include OmniauthSyncer::ControllerHelpers }
    end
  end
end
