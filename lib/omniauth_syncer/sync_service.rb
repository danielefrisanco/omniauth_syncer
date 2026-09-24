# frozen_string_literal: true

module OmniauthSyncer
  # Finds or initialises the local user for an auth hash, copies the mapped
  # attributes onto it and saves it.
  #
  # Returns the saved user, or nil when on_conflict: :ignore refused the sync.
  # Raises MissingIdentityError, ConflictError, ConfigurationError, or the
  # model's own ActiveRecord::RecordInvalid.
  #
  # "Same email, different uid" (another row already holds the incoming email,
  # compared case-insensitively):
  #   :raise  -> ConflictError, nothing written.
  #   :ignore -> nil, nothing written.
  #   :link   -> attach the uid to that row, but only when this identity has no
  #              row yet, the row has no uid, and the provider says the email is
  #              verified; ConflictError otherwise.
  # Every conflict is published as the 'conflict.omniauth_syncer' notification.
  #
  # If a concurrent first login inserts the same user between lookup and save,
  # the resulting ActiveRecord::RecordNotUnique triggers one fresh lookup.
  class SyncService
    # The strategy's list of granted scopes, and the raw userinfo response used
    # to infer them (key presence) when the list is absent.
    GRANTED_SCOPES_PATH = 'extra.scope'
    RAW_INFO_PATH = 'extra.raw_info'

    def self.call(auth_hash)
      new(auth_hash).sync_user
    end

    def initialize(auth_hash)
      @auth_hash = auth_hash
      @config = OmniauthSyncer.configuration
    end

    def sync_user
      @config.validate!
      @user_class = @config.model_class

      identity = identity_attributes
      attributes = mapped_attributes
      retried = false
      begin
        find_and_save(identity, attributes)
      rescue ActiveRecord::RecordNotUnique
        # A concurrent first login inserted the row after our lookup: look it up once more.
        raise if retried

        retried = true
        retry
      end
    end

    private

    def find_and_save(identity, attributes)
      user = @user_class.find_by(identity) || @user_class.new
      conflicting = conflicting_user(user, attributes)
      user = resolve_conflict(conflicting, user) if conflicting
      return if user.nil?

      user.assign_attributes(identity.merge(attributes))
      # A savepoint, so a unique-index failure leaves a surrounding transaction usable for the retry.
      @user_class.transaction(requires_new: true) { user.save! }
      user
    end

    def identity_attributes
      uid = AuthPath.dig(@auth_hash, @config.uid_field_in_auth)
      raise MissingIdentityError, "auth hash has no uid at #{@config.uid_field_in_auth.inspect}" if uid.blank?

      identity = { @config.uid_field => uid.to_s }
      return identity unless @config.provider_field

      provider = AuthPath.dig(@auth_hash, 'provider')
      raise MissingIdentityError, 'auth hash has no provider' if provider.blank?

      identity.merge(@config.provider_field => provider.to_s)
    end

    # nil means "nothing to write" and is skipped, unless clear_blank is on and
    # the provider actually sent the attribute. false, '' and [] are values.
    def mapped_attributes
      @config.mappings.each_with_object({}) do |(attribute, source), attributes|
        value = source.respond_to?(:call) ? source.call(@auth_hash) : AuthPath.dig(@auth_hash, source)
        next if value.nil? && !clearable?(source)

        attributes[attribute.to_sym] = value
      end
    end

    # A callable signals "clear" by returning a non-nil blank value itself.
    def clearable?(source)
      return false if !@config.clear_blank || source.respond_to?(:call)

      scope = @config.path_scopes[source.to_s]
      scope ? scope_granted?(scope, source) : AuthPath.key?(@auth_hash, source)
    end

    def scope_granted?(scope, path)
      granted = AuthPath.dig(@auth_hash, GRANTED_SCOPES_PATH)
      if granted
        scopes = granted.is_a?(String) ? granted.split : Array(granted)
        scopes.map(&:to_s).include?(scope.to_s)
      else
        AuthPath.key?(AuthPath.dig(@auth_hash, RAW_INFO_PATH), path.to_s.split('.').last)
      end
    end

    def conflicting_user(user, attributes)
      email = attributes[@config.email_field.to_sym]
      return if email.blank?

      scope = users_with_email(email)
      scope = scope.where.not(@user_class.primary_key => user.id) if user.persisted?
      scope.first
    end

    # Case-insensitive, with LOWER() on both sides so SQL and Ruby case rules can't disagree.
    def users_with_email(email)
      column = @user_class.arel_table[@config.email_field]
      incoming = Arel::Nodes::NamedFunction.new('LOWER', [Arel::Nodes.build_quoted(email, column)])
      @user_class.where(column.lower.eq(incoming))
    end

    def resolve_conflict(conflicting, user)
      ActiveSupport::Notifications.instrument(
        'conflict.omniauth_syncer',
        policy: @config.on_conflict, uid: AuthPath.dig(@auth_hash, @config.uid_field_in_auth),
        provider: AuthPath.dig(@auth_hash, 'provider'), existing_id: conflicting.id
      )
      case @config.on_conflict
      when :ignore then nil
      when :link then link(conflicting, user)
      else raise conflict_error(conflicting, 'on_conflict is :raise')
      end
    end

    def link(conflicting, user)
      raise conflict_error(conflicting, 'cannot link, this uid already has its own user') if user.persisted?

      existing_uid = conflicting[@config.uid_field]
      raise conflict_error(conflicting, 'cannot link, that user already has a uid') if existing_uid.present?
      raise conflict_error(conflicting, 'cannot link, the email is not verified') unless email_verified?

      conflicting
    end

    def email_verified?
      AuthPath.dig(@auth_hash, @config.email_verified_path) == true
    end

    def conflict_error(conflicting, reason)
      ConflictError.new("#{@user_class.name} ##{conflicting.id} already holds this email (#{reason})")
    end
  end
end
