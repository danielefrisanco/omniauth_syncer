# frozen_string_literal: true

module OmniauthSyncer
  class Configuration
    ON_CONFLICT_POLICIES = %i[raise link ignore].freeze

    # user_model:         ActiveRecord class name the users live in.
    # uid_field:          column holding the provider's uid.
    # uid_field_in_auth:  dotted path to the uid in the auth hash.
    # provider_field:     column holding auth['provider']; when set, users are
    #                     looked up by (provider, uid) instead of uid alone.
    # email_field:        local attribute checked for "same email, different uid".
    # mappings:           local attribute => dotted path or callable(auth).
    # on_conflict:        :raise, :link or :ignore (see SyncService).
    # clear_blank:        write nil when the provider sent the attribute empty.
    # path_scopes:        dotted path => OAuth scope that must be granted before
    #                     clear_blank may clear it.
    # email_verified_path: dotted path to the provider's email_verified flag.
    # include_controller_helpers: include ControllerHelpers into
    #                     ActionController::Base (Rails only).
    attr_accessor :user_model, :uid_field, :uid_field_in_auth, :provider_field, :email_field,
                  :mappings, :on_conflict, :clear_blank, :path_scopes, :email_verified_path,
                  :include_controller_helpers

    def initialize
      @user_model = 'User'
      @uid_field = :uid
      @uid_field_in_auth = 'uid'
      @provider_field = nil
      @email_field = :email
      @mappings = { email: 'info.email', name: 'info.name' }
      @on_conflict = :raise
      @clear_blank = false
      @path_scopes = { 'info.email' => 'email', 'info.name' => 'profile', 'extra.email_verified' => 'email' }
      @email_verified_path = 'extra.email_verified'
      @include_controller_helpers = false
    end

    def model_class
      user_model.to_s.safe_constantize ||
        raise(ConfigurationError, "user_model #{user_model.inspect} is not a defined constant")
    end

    # Raises ConfigurationError with the first problem found; returns true otherwise.
    # Needs the database schema, so call it where a connection is available.
    def validate!
      klass = model_class
      validate_on_conflict!
      validate_mappings!(klass)
      validate_link!
      validate_lookup_columns!(klass)
      true
    end

    private

    def validate_on_conflict!
      return if ON_CONFLICT_POLICIES.include?(on_conflict)

      raise ConfigurationError,
            "on_conflict must be one of #{ON_CONFLICT_POLICIES.map(&:inspect).join(', ')}, got #{on_conflict.inspect}"
    end

    def validate_mappings!(klass)
      raise ConfigurationError, "mappings must be a Hash, got #{mappings.class}" unless mappings.is_a?(Hash)

      klass.define_attribute_methods if klass.respond_to?(:define_attribute_methods)
      mappings.each { |attribute, source| validate_mapping!(klass, attribute, source) }
    end

    def validate_link!
      return if on_conflict != :link || mapped?(email_field)

      raise ConfigurationError, "on_conflict :link needs a mapping for email_field #{email_field.inspect}"
    end

    def validate_mapping!(klass, attribute, source)
      unless klass.method_defined?("#{attribute}=")
        raise ConfigurationError, "#{klass.name} has no writer for mapped attribute #{attribute.inspect}"
      end
      return if source.respond_to?(:call) || (source.is_a?(String) && !source.empty?)

      raise ConfigurationError,
            "mapping #{attribute.inspect} must be a dotted path String or a callable, got #{source.inspect}"
    end

    def validate_lookup_columns!(klass)
      fields = { uid_field: uid_field }
      fields[:provider_field] = provider_field if provider_field
      fields[:email_field] = email_field if mapped?(email_field)
      fields.each do |setting, column|
        next if klass.column_names.include?(column.to_s)

        raise ConfigurationError, "#{klass.name} has no column #{column.inspect} (configured as #{setting})"
      end
    end

    def mapped?(attribute)
      mappings.keys.map(&:to_s).include?(attribute.to_s)
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  def self.validate!
    configuration.validate!
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end
end
