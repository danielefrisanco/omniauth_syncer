module OmniauthSyncer
  class SyncService
    # Use the .call convention for single-purpose service objects
    def self.call(auth_hash)
      new(auth_hash).sync_user
    end

    def sync_user
      # Step 1: Find or Create the User
      user = find_or_initialize_user

      # Step 2: Update Mapped Attributes
      @config.mappings.each do |local_attr, auth_path|
        # Use a helper to safely retrieve nested data (e.g., 'info.email')
        auth_value = get_auth_value(auth_path)

        # Only set if the value is present and the local attribute is writable
        user.send("#{local_attr}=", auth_value) if auth_value.present?
      end

      # Step 3: Save and Return
      user.save! # Use save! to ensure we raise an error on validation failure
      user
    end

    private

    def initialize(auth_hash)
      @auth_hash = auth_hash
      @config = OmniauthSyncer.configuration
      # Dynamically get the User model class
      @user_class = @config.user_model.constantize
    end

    def find_or_initialize_user
      # Get the unique identifier value from the auth hash (e.g., the UID)
      uid_value = get_auth_value(@config.uid_field_in_auth) # Assume config holds the path to UID

      # Use the configured uid_field for the database lookup
      @user_class.find_or_initialize_by(@config.uid_field => uid_value)
    end

    # Helper method to safely traverse the nested AuthHash
    # (Simplified for demonstration; a real implementation would be more robust)
    def get_auth_value(path)
      parts = path.to_s.split('.')
      current = @auth_hash.dup

      parts.each do |part|
        # Use dig for safety, converting to symbol or string keys
        current = current.respond_to?(:dig) ? current.dig(part.to_sym) || current.dig(part.to_s) : current[part]
        return nil unless current
      end
      current
    end
  end
end
