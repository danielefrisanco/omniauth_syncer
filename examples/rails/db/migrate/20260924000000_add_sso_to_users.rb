# frozen_string_literal: true

class AddSsoToUsers < ActiveRecord::Migration[7.2]
  def change
    change_table :users, bulk: true do |t|
      t.string :sso_uid
      t.string :provider
      t.boolean :admin, default: false, null: false
      t.boolean :email_verified
    end
    add_index :users, %i[provider sso_uid], unique: true
  end
end
