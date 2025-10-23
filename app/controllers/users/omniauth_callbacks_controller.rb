# The final controller setup in the user's application
class Users::OmniauthCallbacksController < ApplicationController
  include OmniauthSyncer::ControllerHelpers # Includes the sync_sso_user method

  def sso_provider
    # Use the helper to sync the user and retrieve the record
    @user = sync_sso_user

    sign_in_and_redirect @user, event: :authentication
  rescue StandardError
    redirect_to root_path, alert: 'Authentication failed.'
  end
end
