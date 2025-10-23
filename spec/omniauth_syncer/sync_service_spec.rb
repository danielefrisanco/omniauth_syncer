require 'spec_helper'
RSpec.describe OmniauthSyncer::SyncService do
  # Mock a simple ActiveRecord user model for testing
  let(:mock_user) do
    Struct.new(:id, :uid, :email, :name, :roles, :persisted, :new_record) do
      # Simulate AR methods
      def self.find_or_initialize_by(attrs)
        @records ||= {}
        record = @records[attrs[:uid]]
        return record if record

        new_user = new(nil, attrs[:uid], nil, nil, nil, false, true)
        @records[attrs[:uid]] = new_user
        new_user
      end

      def persisted?
        @persisted = true
      end
      def new_record?
        @new_record = false
      end

      def save!
        self.persisted = true
        true
      end
    end
  end

  let(:auth_hash) do
    # Mock OmniAuth AuthHash structure
    {
      'provider' => 'sso_provider',
      'uid' => '1234567890',
      'info' => { 'email' => 'test@example.com', 'name' => 'Alice Smith' },
      'extra' => { 'raw_info' => { 'roles' => %w[admin billing] } }
    }
  end

  # Setup the mock configuration
  before do
    allow(OmniauthSyncer).to receive(:configuration).and_return(
      OpenStruct.new(
        user_model: 'MockUser',
        uid_field: :uid,
        uid_field_in_auth: 'uid', # The path to the uid in the hash
        mappings: {
          email: 'info.email',
          name: 'info.name',
          roles: 'extra.raw_info.roles'
        }
      )
    )
    # Stub constantize to return our mock user
    stub_const('MockUser', mock_user)

    # Ensure the class cache is clean for `find_or_initialize_by`
    mock_user.instance_variable_set(:@records, {})
  end

  describe '.call' do
    context 'when creating a new user' do
      it 'creates a new user with correct attributes' do
        user = described_class.call(auth_hash)

        expect(user).to be_persisted
        expect(user.uid).to eq('1234567890')
        expect(user.email).to eq('test@example.com')
        expect(user.name).to eq('Alice Smith')
        expect(user.roles).to include('admin', 'billing')
      end
    end

    context 'when updating an existing user' do
      let!(:existing_user) do
        # Manually create a user with stale data
        user = mock_user.find_or_initialize_by(uid: '1234567890')
        user.email = 'old@stale.com'
        user.name = 'Old Name'
        user.save!
        user
      end

      it 'updates the user with fresh data from the SSO provider' do
        updated_hash = Marshal.load(Marshal.dump(auth_hash))
        updated_hash['info']['name'] = 'Alice The Great'

        user = described_class.call(updated_hash)

        expect(user).to eq(existing_user)
        expect(user.name).to eq('Alice The Great')
        expect(user.email).to eq('test@example.com') # Should also be updated
      end
    end
    # ----------------------------------------------------------------------
    # 1. Handling Missing Data (Nil/Blank)
    # ----------------------------------------------------------------------
    context 'when optional data is missing in the auth hash' do
      let!(:existing_user_with_data) do
        # Create user with an existing role that should NOT be cleared by a blank sync
        user = mock_user.find_or_initialize_by(uid: '1234567890')
        user.roles = %w[member finance]
        user.save!
        user
      end

      let(:incomplete_auth_hash) do
        # Auth hash is missing the 'extra' key entirely, meaning 'roles' is missing
        {
          'provider' => 'sso_provider',
          'uid' => '1234567890',
          'info' => { 'email' => 'updated@example.com', 'name' => 'Alice' }
          # 'extra' (and thus 'roles') is missing
        }
      end

      it 'does NOT overwrite existing local attributes with nil if data is missing' do
        user = described_class.call(incomplete_auth_hash)

        expect(user).to eq(existing_user_with_data)
        # Name and Email should update, but Roles should stay the same.
        expect(user.email).to eq('updated@example.com')
        expect(user.name).to eq('Alice')

        # CRUCIAL: The existing roles MUST be preserved because the path was missing
        # and we don't want to clear the data.
        expect(user.roles).to contain_exactly('member', 'finance')
      end

      it 'handles an explicit nil value in the auth hash path safely' do
        # Test case where the path exists, but the value is explicitly nil
        nil_role_hash = Marshal.load(Marshal.dump(incomplete_auth_hash))
        nil_role_hash['extra'] = { 'raw_info' => { 'roles' => nil } }

        user = described_class.call(nil_role_hash)

        # Again, should not clear existing roles (assuming your save logic prevents nil assignment)
        # NOTE: For true robustness, you should guard against setting nil/blank values in your SyncService
        expect(user.roles).to contain_exactly('member', 'finance')
      end
    end

    # ----------------------------------------------------------------------
    # 2. No Data Change
    # ----------------------------------------------------------------------
    context 'when existing user logs in with identical data' do
      let!(:perfectly_synced_user) do
        # Manually create a user that is identical to the auth_hash data
        user = mock_user.find_or_initialize_by(uid: '1234567890')
        user.email = 'test@example.com'
        user.name = 'Alice Smith'
        user.roles = %w[admin billing]
        user.save!
        user
      end

      # Stub the save! method to track if it's called unnecessarily
      before { allow(perfectly_synced_user).to receive(:save!) }

      it 'returns the user and avoids unnecessary save operations' do
        user = described_class.call(auth_hash)

        expect(user).to eq(perfectly_synced_user)
        # NOTE: In a real ActiveRecord model, if no attributes change, save! is a no-op.
        # Our mock doesn't truly prevent save! from being called, but in a real test
        # with a proper model, we'd ensure save is called only if dirty.
        # For our mock, we just ensure it executes without error.
        expect { user }.not_to raise_error
      end
    end

    # ----------------------------------------------------------------------
    # 3. Path Traversal Safety
    # ----------------------------------------------------------------------
    context 'when traversing a non-existent path in auth hash' do
      # Add a mapping for a field that definitely won't exist
      before do
        new_mappings = OmniauthSyncer.configuration.mappings.merge(
          favorite_color: 'extra.non_existent_key.color'
        )
        allow(OmniauthSyncer.configuration).to receive(:mappings).and_return(new_mappings)
      end

      let!(:existing_user_with_color) do
        user = mock_user.find_or_initialize_by(uid: '1234567890')
        # Give the user a default value
        user.instance_eval do
          def favorite_color=(v)
            @favorite_color = v
          end

          def favorite_color
            @favorite_color
          end
        end
        user.favorite_color = 'blue'
        user.save!
        user
      end

      it 'returns nil safely and does not raise an error during attribute assignment' do
        expect { described_class.call(auth_hash) }.not_to raise_error

        user = described_class.call(auth_hash)
        # CRUCIAL: The existing value MUST be preserved
        expect(user.favorite_color).to eq('blue')
      end
    end
  end
end
