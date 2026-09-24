# Changelog

## 0.2.0 — 2026-09-24

### Breaking

- The default `mappings` are now `{ email: 'info.email', name: 'info.name' }` (was `{}`).
- `nil` is the only value skipped when syncing. `false`, `''` and `[]` are now written. In 0.1.0 anything not
  `present?` was skipped, so a revoked flag could never be saved as `false`.
- A blank uid now raises `OmniauthSyncer::MissingIdentityError`. In 0.1.0, `find_or_initialize_by(uid: nil)` could
  return an unrelated user.
- Another row holding the incoming email now raises `OmniauthSyncer::ConflictError` by default. Before, it failed on
  the unique index or created a duplicate. Emails are compared case-insensitively. See `on_conflict`.
- `ControllerHelpers#sync_sso_user` is now private. It logs and re-raises any error, and returns `nil` when the sync
  is refused.
- The `Rails::Engine` is replaced by a Railtie. The example controller and initializer moved from the gem root to
  `examples/rails/`. Under an engine, Rails would have loaded them into every host app.
- Requires Ruby ≥ 3.1 and ActiveSupport ≥ 6.1.

### Added

- `provider_field`: look users up by `(provider, uid)` and store `auth['provider']`.
- `on_conflict: :raise | :link | :ignore` for "same email, different uid". `:link` attaches the uid only when the
  existing row has no uid and `email_verified` is true. Each conflict publishes `conflict.omniauth_syncer`.
- Mappings can be callables. `OmniauthSyncer::Mappings::ADMIN` and `EMAIL_VERIFIED` are ready-made hub mappings.
- `clear_blank`: write `nil` when the provider sent the attribute empty. It checks the granted scopes (`extra.scope`,
  or key presence in `extra.raw_info`) via `path_scopes`.
- `Configuration#validate!` and `OmniauthSyncer.validate!` raise `OmniauthSyncer::ConfigurationError` with a precise
  message. `SyncService` runs the same checks before every sync.
- `include_controller_helpers`: have the Railtie include `ControllerHelpers` into `ActionController::Base`.
- `ControllerHelpers` is required from `omniauth_syncer`.
- Two simultaneous first logins no longer fail with `ActiveRecord::RecordNotUnique`: the losing request retries the
  lookup once. The save runs in a savepoint, so the retry also works inside a host transaction.

### Fixed

- Path lookup no longer turns `false` into `nil`.

### Internal

- New spec suite against an in-memory SQLite database, with auth hash fixtures for strategy 0.2.0 and 0.1.2.
- Added RuboCop config for Ruby 3.1, GitHub Actions CI (Ruby 3.1–3.4), a `Rakefile` and a `.gitignore`.
- README rewritten around the `omniauth-ssoprovider` auth hash.

## 0.1.0

- Initial release.
