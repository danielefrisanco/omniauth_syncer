# omniauth_syncer

Keeps a local ActiveRecord user in step with the OmniAuth auth hash after an SSO login.

On each login, `OmniauthSyncer::SyncService.call(auth_hash)` does four things:

1. It looks up the local user by `(provider, uid)`, or by `uid` alone.
2. It copies the mapped attributes out of the auth hash.
3. It applies an explicit policy when another local user already holds the incoming email.
4. It saves the user with `save!`.

`ControllerHelpers#sync_sso_user` wraps the service for an OmniAuth callback controller.

The gem is written for client apps that sign in through a SecureSSOHub server with
[`omniauth-ssoprovider`](https://github.com/danielefrisanco/omniauth-ssoprovider). It works with any OmniAuth
strategy that fills `uid` and `info`.

Requires Ruby ≥ 3.1 and ActiveSupport ≥ 6.1. The user model must be ActiveRecord.

## Installation

```ruby
gem 'omniauth-ssoprovider'
gem 'omniauth_syncer'
```

## The auth hash

With `omniauth-ssoprovider` 0.2.0, a hub login produces:

```ruby
{
  "provider" => "ssoprovider",                    # or whatever name the strategy is mounted under
  "uid"      => "<sso_id>",                       # stable UUID, the hub's `sub`
  "info"     => { "name" => "…", "email" => "…" }, # each nil without its scope
  "extra"    => {
    "raw_info"       => { "id" => "<sso_id>", "sub" => "<sso_id>", "name" => "…",
                          "email" => "…", "email_verified" => false, "roles" => ["admin"] },
    "access_token"   => "<RS256 JWT, 10 min>",
    "refresh_token"  => "<opaque or nil>",
    "expires_at"     => 1758200000,
    "id_token"       => { "sub" => "…", "iss" => "…", "aud" => "…", "nonce" => "…" },
    "roles"          => ["admin"],                # or []
    "email_verified" => false,
    "scope"          => ["openid", "profile", "email"]
  }
}
```

`omniauth-ssoprovider` 0.1.2 gives the same `provider`, `uid` and `info`. Its `extra` holds only `raw_info` and
`access_token`. The default mappings work with both versions.

Treat `uid` as the only stable identity. Users can change their email on the hub.

## Configuration

```ruby
# config/initializers/omniauth_syncer.rb
OmniauthSyncer.configure do |config|
  config.user_model = 'User'          # default
  config.uid_field = :sso_uid         # column holding the uid; default :uid
  config.uid_field_in_auth = 'uid'    # dotted path in the auth hash; default
  config.provider_field = :provider   # optional: look users up by (provider, uid)

  # Default mappings: { email: 'info.email', name: 'info.name' }
  config.mappings[:admin] = OmniauthSyncer::Mappings::ADMIN
  config.mappings[:email_verified] = OmniauthSyncer::Mappings::EMAIL_VERIFIED

  config.on_conflict = :raise         # :raise (default), :link or :ignore
  config.clear_blank = false          # default
end
```

The host needs the matching columns and unique indexes:

```ruby
add_column :users, :sso_uid, :string
add_column :users, :provider, :string
add_index :users, %i[provider sso_uid], unique: true
add_index :users, :email, unique: true
```

### Mappings

A mapping points a local attribute at a source. The source can be one of two things:

- **A dotted path** such as `'info.email'` or `'extra.raw_info.roles'`. Paths work with string keys, symbol keys and
  `OmniAuth::AuthHash`.
- **A callable** that receives the auth hash, such as `->(auth) { auth['info']['name']&.titleize }`.

Two mappings are ready to use for the hub, and neither is enabled by default:

| Constant | Writes |
| - | - |
| `Mappings::ADMIN` | `true` or `false` from `extra.roles.include?("admin")`. Leaves the attribute untouched when the auth hash has no `extra.roles`, which is the case with strategy 0.1.2. |
| `Mappings::EMAIL_VERIFIED` | `extra.email_verified`. For strategy 0.1.2 use `'extra.raw_info.email_verified'` instead. |

`roles` is the hub's assertion that a user is a hub administrator. It is not an entitlement system.

The hub sends roles only from `/api/v1/userinfo`, so `ADMIN` needs the strategy's `user_info_url:
'/api/v1/userinfo'`. If the strategy uses `/oauth/userinfo` or has userinfo turned off, admins arrive with `roles: []`,
and `ADMIN` revokes their flag.

### Nil values and `clear_blank`

`false`, `''` and `[]` are values and are always written, so a revoked admin or an unverified email is saved as such.

A `nil` value is skipped by default, which keeps the local value.

With `clear_blank = true`, a `nil` is written only when the provider actually sent the attribute:

- **Scoped paths.** `path_scopes` lists paths that depend on a scope. By default `info.email` and
  `extra.email_verified` need `email`, and `info.name` needs `profile`. Such a path is cleared only when its scope was
  granted.
  - When `extra.scope` is present (strategy 0.2.0), the gem reads the granted scopes from it.
  - Otherwise, the gem checks whether `extra.raw_info` has the key. The hub leaves a key out entirely when its scope
    wasn't granted.
- **Other paths.** A path not in `path_scopes` is cleared when its key is present in the auth hash with a `nil` value.
- **Callables.** A callable that returns `nil` never clears anything. Return `''` or `false` to clear.

Without this check, a client that didn't request the `email` scope would wipe every user's email on login.

### Same email, different uid

This happens when no user has the incoming uid, but another row already holds the incoming email. Emails are compared
case-insensitively, so an older `Ada@Example.com` row matches the hub's `ada@example.com`. The same check runs when a
known user changes to an email that another row holds. Typical causes:

- a local account created before SSO,
- a hub account that was deleted and recreated,
- a stale email, where user X changed their email on the hub and user Y took the old address.

| `on_conflict` | Result |
| - | - |
| `:raise` (default) | Raises `OmniauthSyncer::ConflictError` and writes nothing. |
| `:ignore` | Returns `nil` and writes nothing. Treat it as a failed login. |
| `:link` | Attaches the uid to the existing row if three conditions hold: the uid has no row of its own yet, the existing row has no uid, and `email_verified` is `true`. Otherwise it raises `ConflictError`. |

`:link` never overwrites another uid, even when the email is verified. Doing so would hand user X's local account to
user Y.

The hub reports `email_verified: false` for everyone until it gets email confirmation (hub TODO T26). Until then,
`:link` always raises against the hub.

If the same user's first login arrives twice at once, both requests try to insert the row. The one that loses the race
gets `ActiveRecord::RecordNotUnique`, looks the user up once more and updates the row the other request created. This
relies on a unique index on the uid (or `(provider, uid)`) column.

Every conflict publishes a `conflict.omniauth_syncer` notification with the payload `{ policy:, uid:, provider:,
existing_id: }`:

```ruby
ActiveSupport::Notifications.subscribe('conflict.omniauth_syncer') do |event|
  Rails.logger.warn("SSO email conflict: #{event.payload.inspect}")
end
```

### Validation

`SyncService` validates the configuration before every sync. A mistake raises `OmniauthSyncer::ConfigurationError`
with a precise message (for example `User has no writer for mapped attribute :full_name`) instead of a
`NoMethodError`. The checks are:

- `user_model` constantizes,
- the uid, provider and email columns exist,
- every mapped attribute has a writer,
- every mapping is a path or a callable,
- `on_conflict` is a known policy.

To catch mistakes before the first login, call `OmniauthSyncer.validate!` from a spec, a boot check, or a deploy
task. It needs the database schema, so don't call it from `config/initializers`, which also run for `db:create` and
`assets:precompile`.

### Tokens

The gem never stores tokens unless you map them yourself:

- **`extra.access_token`** lives for 10 minutes. Don't persist it. Use it during the callback, or keep it in memory.
- **`extra.refresh_token`**, if you do store it, must be encrypted, for example with `encrypts :sso_refresh_token`
  (Rails 7+ ActiveRecord encryption).

## Callback controller

`sync_sso_user` has three outcomes:

- It returns the saved user.
- It returns `nil` when the `:ignore` policy refuses the sync.
- It logs the error and re-raises it: `OmniauthSyncer::Error` subclasses, or `ActiveRecord::RecordInvalid` from your
  model.

It is a private method, so it never becomes a routable action.

### With Devise

```ruby
# config/initializers/devise.rb (inside Devise.setup)
config.omniauth :ssoprovider, ENV.fetch('SSO_CLIENT_ID'), ENV.fetch('SSO_CLIENT_SECRET'),
                strategy_class: OmniAuth::Strategies::SSOProvider,
                client_options: { site: ENV.fetch('SSO_HUB_URL') },
                user_info_url: '/api/v1/userinfo',
                scope: 'openid profile email'

# config/routes.rb
devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }

# app/models/user.rb
devise :omniauthable, omniauth_providers: %i[ssoprovider]
```

```ruby
# app/controllers/users/omniauth_callbacks_controller.rb
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
```

### Without Devise

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider OmniAuth::Strategies::SSOProvider, ENV.fetch('SSO_CLIENT_ID'), ENV.fetch('SSO_CLIENT_SECRET'),
           client_options: { site: ENV.fetch('SSO_HUB_URL') },
           user_info_url: '/api/v1/userinfo',
           scope: 'openid profile email'
end

# config/routes.rb
get '/auth/:provider/callback', to: 'sessions#create'
get '/auth/failure', to: 'sessions#failure'
```

```ruby
class SessionsController < ApplicationController
  include OmniauthSyncer::ControllerHelpers

  def create
    user = sync_sso_user
    return redirect_to(root_path, alert: 'This email already belongs to another account.') unless user

    reset_session
    session[:user_id] = user.id
    redirect_to root_path
  rescue OmniauthSyncer::Error, ActiveRecord::RecordInvalid
    redirect_to root_path, alert: 'Sign-in failed.'
  end

  def failure
    redirect_to root_path, alert: 'Sign-in failed.'
  end
end
```

OmniAuth 2 starts the login with a POST. Use `button_to '/auth/ssoprovider'` with
`omniauth-rails_csrf_protection`.

To include the helpers in every controller instead of each callback controller, set
`config.include_controller_helpers = true`. The gem's Railtie then includes them into `ActionController::Base`.

The same setup is in [`examples/rails/`](examples/rails/).

## Development

```bash
bundle install
bundle exec rake      # specs + rubocop
bundle exec rake build
```

The specs use an in-memory SQLite database, so no Rails app is needed. Fixture auth hashes for strategy 0.2.0 and
0.1.2 are in `spec/fixtures/`.

## License

MIT
