# frozen_string_literal: true

# Devise host app. Routes:
#   devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
# Model:
#   devise :omniauthable, omniauth_providers: %i[ssoprovider]
module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    include OmniauthSyncer::ControllerHelpers

    # Named after the provider the strategy is mounted as.
    def ssoprovider
      user = sync_sso_user
      return refuse('This email already belongs to another account.') unless user

      sign_in_and_redirect user, event: :authentication
    rescue OmniauthSyncer::Error, ActiveRecord::RecordInvalid
      refuse('Sign-in failed.')
    end

    def failure
      refuse('Sign-in failed.')
    end

    private

    def refuse(message)
      redirect_to new_user_session_path, alert: message
    end
  end
end
