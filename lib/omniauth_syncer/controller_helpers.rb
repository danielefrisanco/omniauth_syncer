module OmniauthSyncer
  module ControllerHelpers
    # Call this method inside the OmniAuth callback action
    def sync_sso_user
      # Retrieve the auth hash from the Rack environment
      auth_hash = request.env['omniauth.auth']

      # Execute the core sync logic
      OmniauthSyncer::SyncService.call(auth_hash)
    rescue ActiveRecord::RecordInvalid => e
      # Provide a clear, common way to handle sync validation errors
      logger.error "OmniauthSyncer Validation Error: #{e.message}"
      # Optionally, you might raise a custom error here
      raise e
    end
  end
end
