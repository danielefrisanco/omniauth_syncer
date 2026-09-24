# frozen_string_literal: true

OmniauthSyncer.configure do |config|
  config.user_model = 'User'
  config.uid_field = :sso_uid
  config.provider_field = :provider

  # Defaults: { email: 'info.email', name: 'info.name' }
  config.mappings[:admin] = OmniauthSyncer::Mappings::ADMIN
  config.mappings[:email_verified] = OmniauthSyncer::Mappings::EMAIL_VERIFIED

  config.on_conflict = :raise
  config.clear_blank = true
end
