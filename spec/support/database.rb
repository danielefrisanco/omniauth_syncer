# frozen_string_literal: true

require 'active_record'
require 'logger'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = nil
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :uid
    t.string :provider
    t.string :email
    t.string :name
    t.boolean :admin, default: false, null: false
    t.boolean :email_verified
    t.string :legacy_note
  end
  add_index :users, %i[provider uid], unique: true
  add_index :users, :email, unique: true
end

class User < ActiveRecord::Base
  validates :email, presence: true
end

RSpec.configure do |config|
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
