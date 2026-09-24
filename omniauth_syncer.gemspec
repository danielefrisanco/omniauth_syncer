# frozen_string_literal: true

require_relative 'lib/omniauth_syncer/version'

Gem::Specification.new do |spec|
  spec.name          = 'omniauth_syncer'
  spec.version       = OmniauthSyncer::VERSION
  spec.authors       = ['Daniele Frisanco']
  spec.email         = ['daniele.frisanco@gmail.com']

  spec.summary       = 'Keeps a local ActiveRecord user in step with the OmniAuth auth hash after an SSO login.'
  spec.description   = 'Finds or creates the local user by (provider, uid), copies mapped attributes out of the ' \
                       'OmniAuth auth hash and saves it, with explicit policies for email conflicts and cleared values.'
  spec.homepage      = 'https://github.com/danielefrisanco/omniauth_syncer'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files         = Dir['lib/**/*.rb', 'README.md', 'CHANGELOG.md', 'LICENSE.txt']
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 6.1'
  spec.add_dependency 'omniauth', '~> 2.0'
end
