# frozen_string_literal: true

RSpec.describe OmniauthSyncer::ControllerHelpers do
  let(:controller_class) do
    Class.new do
      include OmniauthSyncer::ControllerHelpers

      attr_reader :request, :logger

      def initialize(auth_hash, logger)
        @request = Struct.new(:env).new({ 'omniauth.auth' => auth_hash })
        @logger = logger
      end

      def callback
        sync_sso_user
      end
    end
  end
  let(:logger) { instance_double(Logger, warn: nil, error: nil) }
  let(:auth) { OmniAuth::AuthHash.new(auth_fixture('auth_hash_0_2_0')) }

  it 'keeps sync_sso_user out of the public (routable) interface' do
    expect(controller_class.public_method_defined?(:sync_sso_user)).to be(false)
  end

  it 'syncs the user from request.env["omniauth.auth"]' do
    user = controller_class.new(auth, logger).callback

    expect(user).to be_persisted.and have_attributes(uid: auth['uid'], email: 'alice@example.com')
  end

  it 'returns nil and logs a warning when the sync is refused' do
    OmniauthSyncer.configuration.on_conflict = :ignore
    User.create!(uid: 'someone-else', email: 'alice@example.com')

    expect(controller_class.new(auth, logger).callback).to be_nil
    expect(logger).to have_received(:warn).with(/sync refused/)
  end

  it 'logs and re-raises sync errors' do
    auth['uid'] = ''

    expect { controller_class.new(auth, logger).callback }.to raise_error(OmniauthSyncer::MissingIdentityError)
    expect(logger).to have_received(:error).with(/MissingIdentityError/)
  end
end
