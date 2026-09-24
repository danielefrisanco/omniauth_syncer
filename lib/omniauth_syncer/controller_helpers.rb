# frozen_string_literal: true

module OmniauthSyncer
  module ControllerHelpers
    private

    # Call this inside the OmniAuth callback action. Returns the synced user, or
    # nil when the sync was refused (on_conflict: :ignore); treat nil as a
    # failed login. Errors are logged and re-raised.
    def sync_sso_user
      user = OmniauthSyncer::SyncService.call(request.env['omniauth.auth'])
      logger&.warn('OmniauthSyncer: sync refused, email belongs to another local user') if user.nil?
      user
    rescue StandardError => e
      logger&.error("OmniauthSyncer: #{e.class}: #{e.message}")
      raise
    end
  end
end
