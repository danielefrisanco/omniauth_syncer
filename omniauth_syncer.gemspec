$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'omniauth_syncer/version'

Gem::Specification.new do |spec|
  spec.name          = "omniauth_syncer"
  spec.version       = OmniauthSyncer::VERSION
  spec.authors       = ["Daniele Frisanco"]
  spec.email         = ["daniele.frisanco@gmail.com"]

  spec.summary       = "A Ruby gem for synchronizing user profile data from OmniAuth to local ActiveRecord models."
  spec.description   = "Ensures local user records are created or updated with the latest data from the SSO provider after a successful OmniAuth login."
  spec.homepage      = "https://github.com/danielefrisanco/omniauth_syncer"

  spec.license       = "MIT"

  # Ensure all necessary files are included when the gem is built
  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == "omniauth_syncer.gemspec") ||
      f.match(%r{^(test|spec|features)/})
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Define dependencies (you'll need a JWT library for the *next* gem, but for this one, you mainly need OmniAuth and Rails/ActiveSupport helpers)
  spec.add_dependency "omniauth", "~> 2.0" 
  spec.add_dependency "activesupport", ">= 6.0" # For utilities like constantize and deep_dup
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pry" # Useful for debugging
end