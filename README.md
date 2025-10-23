omniauth\_syncer 🚀
===================

A plug-and-play Ruby gem designed for applications using **OmniAuth** (often with SSO providers) to reliably and safely synchronize user profile data into a local $\\text{ActiveRecord}$ model.

This gem prevents data drift by ensuring the local user record is always up-to-date with the latest information fetched from the SSO provider during a successful login.

Installation
------------

Add this line to your application's Gemfile:

Ruby

```ruby
gem 'omniauth_syncer'
```

Then execute:

Bash

```bash
bundle install   
```

Configuration
-------------

The gem requires a basic setup to know which local model to use and how to map fields from the OmniAuth hash.

Create an initializer file at config/initializers/omniauth\_syncer.rb:

Ruby

```ruby
# config/initializers/omniauth_syncer.rb
OmniauthSyncer.configure do |config|
  # 1. Local User Model
  # The name of the local ActiveRecord class to sync data to (e.g., 'User')
  config.user_model = 'User'
  # 2. Unique Identifier Field
  # The column in your local User model used for lookup (must be unique).
  config.uid_field = :sso_uid
  # 3. Path to UID in Auth Hash
  # The string path in the OmniAuth Auth Hash that holds the unique identifier.
  # Example: 'uid' is used for the top-level hash['uid'].
  config.uid_field_in_auth = 'uid'
  # 4. Attribute Mappings
  # Map local attributes (keys) to the path in the OmniAuth Auth Hash (values).
  # Use dot notation for nested fields (e.g., 'info.email').
  config.mappings = {
    email: 'info.email',
    full_name: 'info.name',
    # Example for nested data like roles provided by the SSO server:
    roles: 'extra.raw_info.roles'
  }
end   
```

Usage
-----

The gem provides the core synchronization logic via a helper module, which should be included in your application's **OmniAuth Callback Controller**.

### Step 1: Include the Helper

In your OmniAuth Callback Controller (e.g., app/controllers/users/omniauth\_callbacks\_controller.rb):

Ruby

```ruby
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # Include the helper module
  include OmniauthSyncer::ControllerHelpers
  # ...
end   
```

### Step 2: Sync the User

Call the **sync\_sso\_user** method inside your provider action (e.g., sso\_provider). This method will handle the following automatically:

1.  Retrieving the current $\\text{OmniAuth Auth Hash}$.
    
2.  Calling the $\\text{SyncService}$ to $\\text{find or create}$ the local user record based on the configured $\\text{uid}$.
    
3.  Updating all configured attributes.
    
4.  Safely **preserving** existing local data if a field is missing or nil in the incoming SSO data.
    

Ruby

```ruby
# app/controllers/users/omniauth_callbacks_controller.rb
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include OmniauthSyncer::ControllerHelpers
  def sso_provider
    begin
      # 1. Sync the user and get the local user object
      @user = sync_sso_user
      # 2. Sign in the user (e.g., using Devise or a custom method)
      if @user.persisted?
        sign_in_and_redirect @user, event: :authentication
      else
        # This occurs if the user record fails local validations (e.g., missing mandatory field)
        redirect_to root_path, alert: "Could not sync user profile due to data issues."
      end
    rescue => e
      # Log any synchronization or validation errors
      logger.error "SSO Sync Failure: #{e.message}"
      redirect_to root_path, alert: "Authentication failed due to internal error."
    end
  end
end   
```

Contributing
------------

Bug reports and pull requests are welcome on GitHub at https://github.com/danielefrisanco/omniauth_syncer.

License
-------

The gem is available as open source under the terms of the **MIT License**.