OmniauthSyncer.configure do |config|
  # The ActiveRecord model class name
  config.user_model = 'User'

  # The column used for the unique identifier
  config.uid_field = :sso_id

  # Mapping: local_attribute => path_in_auth_hash
  # 'info.email' looks into auth_hash.info['email']
  config.mappings = {
    email: 'info.email',
    full_name: 'info.name',
    # Example for nested/extra data: auth_hash.extra['raw_info']['roles']
    roles: 'extra.raw_info.roles'
  }
end
