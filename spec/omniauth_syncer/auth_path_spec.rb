# frozen_string_literal: true

RSpec.describe OmniauthSyncer::AuthPath do
  let(:auth) do
    { 'uid' => '42', 'info' => { 'email' => 'a@example.com', 'name' => nil },
      'extra' => { 'email_verified' => false, 'roles' => [], 'raw_info' => { 'roles' => ['admin'] } } }
  end

  describe '.dig' do
    it 'reads top-level and nested values' do
      expect(described_class.dig(auth, 'uid')).to eq('42')
      expect(described_class.dig(auth, 'info.email')).to eq('a@example.com')
      expect(described_class.dig(auth, 'extra.raw_info.roles')).to eq(['admin'])
    end

    it 'returns nil for missing keys at any depth' do
      expect(described_class.dig(auth, 'nope')).to be_nil
      expect(described_class.dig(auth, 'extra.nope.deeper')).to be_nil
    end

    it 'returns nil when an intermediate value is not a hash' do
      expect(described_class.dig(auth, 'uid.length')).to be_nil
      expect(described_class.dig(auth, 'extra.roles.first')).to be_nil
    end

    it 'keeps false and empty values' do
      expect(described_class.dig(auth, 'extra.email_verified')).to be(false)
      expect(described_class.dig(auth, 'extra.roles')).to eq([])
    end

    it 'reads symbol keys' do
      expect(described_class.dig({ info: { email: 'sym@example.com' } }, 'info.email')).to eq('sym@example.com')
    end

    it 'prefers the string key when both exist' do
      expect(described_class.dig({ 'uid' => 'string', uid: 'symbol' }, 'uid')).to eq('string')
    end

    it 'reads an OmniAuth::AuthHash' do
      auth_hash = OmniAuth::AuthHash.new(auth_fixture('auth_hash_0_2_0'))

      expect(described_class.dig(auth_hash, 'info.email')).to eq('alice@example.com')
      expect(described_class.dig(auth_hash, 'extra.email_verified')).to be(false)
      expect(described_class.dig(auth_hash, 'extra.id_token.iss')).to eq('https://hub.example.com')
    end

    it 'returns nil for a nil auth hash' do
      expect(described_class.dig(nil, 'uid')).to be_nil
    end
  end

  describe '.key?' do
    it 'is true for a key present with a nil value' do
      expect(described_class.key?(auth, 'info.name')).to be(true)
    end

    it 'is false for a missing key' do
      expect(described_class.key?(auth, 'info.nickname')).to be(false)
      expect(described_class.key?(auth, 'missing.name')).to be(false)
    end
  end
end
