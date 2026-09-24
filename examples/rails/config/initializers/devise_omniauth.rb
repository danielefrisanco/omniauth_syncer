# frozen_string_literal: true

# Inside Devise.setup in config/initializers/devise.rb.
Devise.setup do |config|
  config.omniauth :ssoprovider, ENV.fetch('SSO_CLIENT_ID'), ENV.fetch('SSO_CLIENT_SECRET'),
                  strategy_class: OmniAuth::Strategies::SSOProvider,
                  client_options: { site: ENV.fetch('SSO_HUB_URL') },
                  user_info_url: '/api/v1/userinfo', # the only endpoint that returns roles
                  scope: 'openid profile email'
end
