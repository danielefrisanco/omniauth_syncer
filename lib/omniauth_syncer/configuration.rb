module OmniauthSyncer
  class Configuration
    # Define settings with default values or required accessors
    attr_accessor :user_model, :uid_field, :uid_field_in_auth, :mappings

    def initialize
      # Sensible defaults
      @user_model = 'User'
      @uid_field = :uid
      @uid_field_in_auth = 'uid' # Default path in AuthHash
      @mappings = {}
    end
  end

  # Class method to expose the configuration object and the configuration block
  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
