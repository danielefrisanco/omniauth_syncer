# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'
require 'active_support/notifications'

require 'omniauth_syncer/version'

module OmniauthSyncer
  class Error < StandardError; end

  # The configuration cannot work against the configured model.
  class ConfigurationError < Error; end

  # The auth hash carries no usable uid (or provider, when provider_field is set).
  class MissingIdentityError < Error; end

  # Another local user already holds the incoming email.
  class ConflictError < Error; end
end

require 'omniauth_syncer/auth_path'
require 'omniauth_syncer/configuration'
require 'omniauth_syncer/mappings'
require 'omniauth_syncer/sync_service'
require 'omniauth_syncer/controller_helpers'
require 'omniauth_syncer/railtie' if defined?(Rails::Railtie)
