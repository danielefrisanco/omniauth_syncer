# frozen_string_literal: true

RSpec.describe OmniauthSyncer::Configuration do
  subject(:config) { OmniauthSyncer.configuration }

  it 'defaults to the hub auth hash' do
    expect(config).to have_attributes(
      user_model: 'User', uid_field: :uid, uid_field_in_auth: 'uid', provider_field: nil,
      email_field: :email, mappings: { email: 'info.email', name: 'info.name' },
      on_conflict: :raise, clear_blank: false, include_controller_helpers: false
    )
  end

  it 'is set through OmniauthSyncer.configure' do
    OmniauthSyncer.configure { |c| c.on_conflict = :ignore }

    expect(config.on_conflict).to eq(:ignore)
  end

  describe '#validate!' do
    it 'accepts the defaults against a matching model' do
      expect(config.validate!).to be(true)
    end

    it 'accepts callables and a provider column' do
      config.provider_field = :provider
      config.mappings[:admin] = OmniauthSyncer::Mappings::ADMIN

      expect(OmniauthSyncer.validate!).to be(true)
    end

    it 'rejects a model that does not constantize' do
      config.user_model = 'Usr'

      expect { config.validate! }
        .to raise_error(OmniauthSyncer::ConfigurationError, 'user_model "Usr" is not a defined constant')
    end

    it 'rejects a missing uid column' do
      config.uid_field = :sso_id

      expect { config.validate! }
        .to raise_error(OmniauthSyncer::ConfigurationError, 'User has no column :sso_id (configured as uid_field)')
    end

    it 'rejects a missing provider column' do
      config.provider_field = :auth_provider

      expect { config.validate! }.to raise_error(
        OmniauthSyncer::ConfigurationError, 'User has no column :auth_provider (configured as provider_field)'
      )
    end

    it 'rejects a mapped attribute without a writer' do
      config.mappings[:full_name] = 'info.name'

      expect { config.validate! }.to raise_error(
        OmniauthSyncer::ConfigurationError, 'User has no writer for mapped attribute :full_name'
      )
    end

    it 'rejects a mapping that is neither a path nor a callable' do
      config.mappings[:name] = :info

      expect { config.validate! }.to raise_error(
        OmniauthSyncer::ConfigurationError, 'mapping :name must be a dotted path String or a callable, got :info'
      )
    end

    it 'rejects an unknown on_conflict policy' do
      config.on_conflict = :merge

      expect { config.validate! }.to raise_error(
        OmniauthSyncer::ConfigurationError, 'on_conflict must be one of :raise, :link, :ignore, got :merge'
      )
    end

    it 'rejects :link without an email mapping' do
      config.on_conflict = :link
      config.mappings = { name: 'info.name' }

      expect { config.validate! }.to raise_error(
        OmniauthSyncer::ConfigurationError, 'on_conflict :link needs a mapping for email_field :email'
      )
    end
  end
end
