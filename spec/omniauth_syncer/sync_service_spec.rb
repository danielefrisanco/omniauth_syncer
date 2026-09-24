# frozen_string_literal: true

RSpec.describe OmniauthSyncer::SyncService do
  let(:config) { OmniauthSyncer.configuration }
  let(:auth) { auth_fixture('auth_hash_0_2_0') }
  let(:uid) { auth['uid'] }

  def sync(hash = auth)
    described_class.call(hash)
  end

  describe 'creating and updating' do
    it 'creates a user from the 0.2.0 auth hash' do
      user = sync

      expect(user).to be_persisted
      expect(user).to have_attributes(uid: uid, email: 'alice@example.com', name: 'Alice Smith', admin: false)
    end

    it 'creates a user from the 0.1.2 auth hash with the default mappings' do
      user = sync(auth_fixture('auth_hash_0_1_2'))

      expect(user).to have_attributes(uid: uid, email: 'alice@example.com', name: 'Alice Smith')
    end

    it 'accepts an OmniAuth::AuthHash and symbol-keyed hashes' do
      expect(sync(OmniAuth::AuthHash.new(auth)).email).to eq('alice@example.com')
      expect(sync(auth.deep_symbolize_keys).uid).to eq(uid)
      expect(User.count).to eq(1)
    end

    it 'updates the existing user found by uid, including a changed email' do
      existing = User.create!(uid: uid, email: 'old@example.com', name: 'Old Name')

      user = sync

      expect(user).to eq(existing)
      expect(user.reload).to have_attributes(email: 'alice@example.com', name: 'Alice Smith')
      expect(User.count).to eq(1)
    end

    it 'does not persist extra.access_token anywhere by default' do
      user = sync

      expect(user.attributes.values).not_to include(auth['extra']['access_token'])
    end

    it 'raises the model validation error' do
      auth['info']['email'] = nil
      auth['extra']['scope'] = %w[openid profile]

      expect { sync }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'identity' do
    it 'refuses an auth hash without a uid' do
      auth['uid'] = ''

      expect { sync }.to raise_error(OmniauthSyncer::MissingIdentityError, 'auth hash has no uid at "uid"')
      expect(User.count).to eq(0)
    end

    it 'does not match users with a nil uid when the auth hash has none' do
      User.create!(uid: nil, email: 'legacy@example.com')
      auth.delete('uid')

      expect { sync }.to raise_error(OmniauthSyncer::MissingIdentityError)
    end

    it 'reads the uid from a configured path' do
      config.uid_field_in_auth = 'extra.raw_info.sub'
      auth['uid'] = nil

      expect(sync.uid).to eq(auth['extra']['raw_info']['sub'])
    end

    context 'with provider_field' do
      before { config.provider_field = :provider }

      it 'stores auth["provider"] and looks users up by (provider, uid)' do
        other = User.create!(provider: 'other_idp', uid: uid, email: 'other@example.com')

        user = sync

        expect(user).not_to eq(other)
        expect(user).to have_attributes(provider: 'ssoprovider', uid: uid)
        expect(sync).to eq(user)
        expect(User.count).to eq(2)
      end

      it 'uses whatever name the strategy was mounted under' do
        auth['provider'] = 'company_sso'

        expect(sync.provider).to eq('company_sso')
      end

      it 'refuses an auth hash without a provider' do
        auth.delete('provider')

        expect { sync }.to raise_error(OmniauthSyncer::MissingIdentityError, 'auth hash has no provider')
      end
    end

    it 'looks users up by uid alone without provider_field' do
      existing = User.create!(provider: 'other_idp', uid: uid, email: 'old@example.com')

      expect(sync).to eq(existing)
    end
  end

  describe 'nil and blank values' do
    let!(:existing) { User.create!(uid: uid, email: 'alice@example.com', name: 'Alice Smith', email_verified: true) }

    context 'with clear_blank: false (default)' do
      it 'keeps local values the provider sent as nil' do
        auth['info']['name'] = nil
        auth['extra']['raw_info']['name'] = nil

        expect(sync.reload.name).to eq('Alice Smith')
      end

      it 'keeps local values for paths missing from the auth hash' do
        config.mappings[:legacy_note] = 'extra.raw_info.note'
        existing.update!(legacy_note: 'keep me')

        expect(sync.reload.legacy_note).to eq('keep me')
      end

      it 'writes false, which is a value and not blank' do
        config.mappings[:email_verified] = OmniauthSyncer::Mappings::EMAIL_VERIFIED

        expect(sync.reload.email_verified).to be(false)
      end

      it 'writes an empty string' do
        auth['info']['name'] = ''

        expect(sync.reload.name).to eq('')
      end
    end

    context 'with clear_blank: true' do
      before { config.clear_blank = true }

      it 'clears a nil value when its scope was granted (extra.scope)' do
        auth['info']['name'] = nil

        expect(sync.reload.name).to be_nil
      end

      it 'keeps the value when its scope was not granted (extra.scope)' do
        auth['info']['name'] = nil
        auth['extra']['scope'] = %w[openid email]

        expect(sync.reload.name).to eq('Alice Smith')
      end

      it 'accepts extra.scope as a space-separated string' do
        auth['info']['name'] = nil
        auth['extra']['scope'] = 'openid email'

        expect(sync.reload.name).to eq('Alice Smith')
      end

      context 'without extra.scope (strategy 0.1.2)' do
        let(:auth) { auth_fixture('auth_hash_0_1_2') }

        it 'clears when raw_info has the key with a nil value (scope granted)' do
          auth['info']['name'] = nil
          auth['extra']['raw_info']['name'] = nil

          expect(sync.reload.name).to be_nil
        end

        it 'keeps the value when raw_info lacks the key (scope not granted)' do
          auth['info']['name'] = nil
          auth['extra']['raw_info'].delete('name')

          expect(sync.reload.name).to eq('Alice Smith')
        end
      end

      it 'clears an unscoped path only when its key is present' do
        config.mappings[:legacy_note] = 'extra.raw_info.note'
        existing.update!(legacy_note: 'old')

        expect(sync.reload.legacy_note).to eq('old')

        auth['extra']['raw_info']['note'] = nil
        expect(sync.reload.legacy_note).to be_nil
      end

      it 'never clears on a nil returned by a callable' do
        config.mappings[:name] = ->(_auth) {}

        expect(sync.reload.name).to eq('Alice Smith')
      end
    end
  end

  describe 'callable mappings' do
    before { config.mappings[:admin] = OmniauthSyncer::Mappings::ADMIN }

    it 'passes the auth hash to the callable' do
      config.mappings[:name] = ->(hash) { hash['info']['name'].upcase }

      expect(sync.name).to eq('ALICE SMITH')
    end

    it 'grants admin from extra.roles' do
      expect(sync.admin).to be(true)
    end

    it 'revokes admin when the role is gone' do
      User.create!(uid: uid, email: 'alice@example.com', admin: true)
      auth['extra']['roles'] = []

      expect(sync.reload.admin).to be(false)
    end

    it 'leaves admin untouched when extra.roles is missing (strategy 0.1.2)' do
      User.create!(uid: uid, email: 'alice@example.com', admin: true)

      expect(sync(auth_fixture('auth_hash_0_1_2')).reload.admin).to be(true)
    end

    it 'handles extra.roles: nil' do
      auth['extra']['roles'] = nil

      expect(sync.admin).to be(false)
    end
  end

  describe 'same email, different uid' do
    let!(:holder) { User.create!(uid: nil, email: 'alice@example.com', name: 'Pre-SSO Alice') }

    context 'with on_conflict: :raise (default)' do
      it 'raises and writes nothing' do
        expect { sync }.to raise_error(OmniauthSyncer::ConflictError, /User ##{holder.id} already holds this email/)
        expect(holder.reload.uid).to be_nil
        expect(User.count).to eq(1)
      end

      it 'matches the email case-insensitively' do
        holder.update!(email: 'Alice@Example.COM')

        expect { sync }.to raise_error(OmniauthSyncer::ConflictError)
        expect(User.count).to eq(1)
      end

      it 'also applies when an existing user changes to an email held by another row' do
        User.create!(uid: uid, email: 'old@example.com')

        expect { sync }.to raise_error(OmniauthSyncer::ConflictError)
      end
    end

    context 'with on_conflict: :ignore' do
      before { config.on_conflict = :ignore }

      it 'returns nil, writes nothing and publishes a notification' do
        events = []
        callback = ->(*args) { events << ActiveSupport::Notifications::Event.new(*args) }

        result = ActiveSupport::Notifications.subscribed(callback, 'conflict.omniauth_syncer') { sync }

        expect(result).to be_nil
        expect(User.count).to eq(1)
        expect(events.map(&:payload)).to contain_exactly(
          { policy: :ignore, uid: uid, provider: 'ssoprovider', existing_id: holder.id }
        )
      end
    end

    context 'with on_conflict: :link' do
      before { config.on_conflict = :link }

      it 'attaches the uid to a pre-SSO row when the email is verified' do
        auth['extra']['email_verified'] = true

        user = sync

        expect(user).to eq(holder)
        expect(user.reload).to have_attributes(uid: uid, name: 'Alice Smith')
        expect(User.count).to eq(1)
      end

      it 'raises when the email is not verified' do
        expect { sync }.to raise_error(OmniauthSyncer::ConflictError, /the email is not verified/)
        expect(holder.reload.uid).to be_nil
      end

      it 'raises when the row already has another uid, even with a verified email' do
        holder.update!(uid: 'stale-user-x')
        auth['extra']['email_verified'] = true

        expect { sync }.to raise_error(OmniauthSyncer::ConflictError, /that user already has a uid/)
        expect(holder.reload.uid).to eq('stale-user-x')
      end

      it 'raises when this uid already has its own row' do
        User.create!(uid: uid, email: 'old@example.com')
        auth['extra']['email_verified'] = true

        expect { sync }.to raise_error(OmniauthSyncer::ConflictError, /this uid already has its own user/)
      end

      it 'reads email_verified from a configured path' do
        config.email_verified_path = 'extra.raw_info.email_verified'
        auth['extra']['raw_info']['email_verified'] = true

        expect(sync).to eq(holder)
      end
    end
  end

  describe 'concurrent first logins' do
    before { config.provider_field = :provider }

    # Makes the first new record's save! lose the race, the way a second request
    # inserting between our lookup and our insert would.
    def race_first_save
      racing = true
      allow(User).to receive(:new).and_wrap_original do |original, *args, &block|
        record = original.call(*args, &block)
        if racing
          racing = false
          allow(record).to receive(:save!).and_wrap_original do |save|
            yield
            save.call
          end
        end
        record
      end
    end

    it 'retries the lookup once and updates the row the other request created' do
      race_first_save { User.create!(provider: 'ssoprovider', uid: uid, email: 'alice@example.com', name: 'Other') }

      user = sync

      expect(user.reload).to have_attributes(uid: uid, name: 'Alice Smith')
      expect(User.count).to eq(1)
    end

    it 'gives up after one retry' do
      allow(User).to receive(:new).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |record| allow(record).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique) }
      end

      expect { sync }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(User).to have_received(:new).twice
    end
  end

  it 'validates the configuration before syncing' do
    config.mappings[:nickname] = 'info.nickname'

    expect { sync }.to raise_error(OmniauthSyncer::ConfigurationError, /no writer for mapped attribute :nickname/)
  end
end
