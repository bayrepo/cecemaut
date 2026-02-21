require 'sequel'
require 'digest'

Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id
      String :login, null: false, unique: true
      String :password, null: false
      String :email
      Integer :role, null: false
      DateTime :create_at, default: Sequel.lit('CURRENT_TIMESTAMP')
    end

    self[:users].insert(login: 'admin', password: Digest::SHA256.hexdigest('admin'), role: 2, email: 'admin@admin')
  end
end
