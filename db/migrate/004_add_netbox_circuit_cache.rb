# frozen_string_literal: true

class AddNetboxCircuitCache < ActiveRecord::Migration[6.1]
  def up
    create_table :service_assurance_netbox_circuits do |t|
      t.integer :nb_id, null: false
      t.integer :provider_id
      t.string :provider_name
      t.text :cid_original
      t.string :circuit_type
      t.string :status
      t.integer :commit_rate_raw
      t.string :capacity_unit, default: 'Kbps'
      t.text :description
      t.text :endpoints_json
      t.string :url
      t.datetime :nb_updated_at
      t.datetime :synced_at
      t.boolean :in_inventory, default: true, null: false
      t.timestamps
    end
    add_index :service_assurance_netbox_circuits, :nb_id, unique: true, name: 'idx_sanb_nb_unique'
    add_index :service_assurance_netbox_circuits, :provider_name, name: 'idx_sanb_provider'
  end

  def down
    remove_index :service_assurance_netbox_circuits, name: 'idx_sanb_provider' if index_exists?(:service_assurance_netbox_circuits, :provider_name, name: 'idx_sanb_provider')
    remove_index :service_assurance_netbox_circuits, name: 'idx_sanb_nb_unique' if index_exists?(:service_assurance_netbox_circuits, :nb_id, name: 'idx_sanb_nb_unique')
    drop_table :service_assurance_netbox_circuits if table_exists?(:service_assurance_netbox_circuits)
  end
end
