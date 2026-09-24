# frozen_string_literal: true

module OmniauthSyncer
  # Dotted-path lookup into an auth hash ('info.email', 'extra.raw_info.roles').
  # Works on plain Hashes with string or symbol keys and on OmniAuth::AuthHash.
  # Unlike `a || b` lookups it keeps `false` values, and it can tell a key that
  # is present with a nil value from a key that is missing.
  module AuthPath
    MISSING = Object.new.freeze
    private_constant :MISSING

    module_function

    def dig(auth, path)
      value = lookup(auth, path)
      value.equal?(MISSING) ? nil : value
    end

    def key?(auth, path)
      !lookup(auth, path).equal?(MISSING)
    end

    def lookup(auth, path)
      path.to_s.split('.').reduce(auth) do |node, segment|
        break MISSING unless node.respond_to?(:key?)

        if node.key?(segment)
          node[segment]
        elsif node.key?(segment.to_sym)
          node[segment.to_sym]
        else
          break MISSING
        end
      end
    end
    private_class_method :lookup
  end
end
