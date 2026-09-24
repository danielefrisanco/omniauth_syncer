# frozen_string_literal: true

module OmniauthSyncer
  # Opt-in mappings for the auth hash omniauth-ssoprovider builds from a hub login.
  #
  #   config.mappings[:admin] = OmniauthSyncer::Mappings::ADMIN
  #   config.mappings[:email_verified] = OmniauthSyncer::Mappings::EMAIL_VERIFIED
  module Mappings
    # true/false from the hub's role assertion, nil (left untouched) when the
    # auth hash has no extra.roles. The hub sends roles only from
    # /api/v1/userinfo, so the strategy must use that user_info_url; against
    # /oauth/userinfo every user, admins included, arrives with roles [].
    ADMIN = lambda do |auth|
      Array(AuthPath.dig(auth, 'extra.roles')).include?('admin') if AuthPath.key?(auth, 'extra.roles')
    end

    EMAIL_VERIFIED = 'extra.email_verified'
  end
end
