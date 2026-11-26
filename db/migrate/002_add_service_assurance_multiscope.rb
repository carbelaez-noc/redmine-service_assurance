# frozen_string_literal: true

class AddServiceAssuranceMultiscope < ActiveRecord::Migration[6.1]
  def up
    add_column :service_assurance_cases, :assignee_id, :integer unless column_exists?(:service_assurance_cases, :assignee_id)
    add_column :service_assurance_cases, :original_snapshot, :text unless column_exists?(:service_assurance_cases, :original_snapshot)
    add_column :service_assurance_cases, :lock_version, :integer, default: 0, null: false unless column_exists?(:service_assurance_cases, :lock_version)
    add_column :service_assurance_evaluations, :lock_version, :integer, default: 0, null: false unless column_exists?(:service_assurance_evaluations, :lock_version)
    add_index :service_assurance_cases, :assignee_id, name: 'idx_sac_assignee' unless index_exists?(:service_assurance_cases, nil, name: 'idx_sac_assignee')

    create_table :service_assurance_circuits do |t|
      t.integer :case_id, null: false
      t.string :circuit, null: false
      t.string :external_case
      t.string :external_verified, default: 'pendiente'
      t.timestamps
    end
    add_index :service_assurance_circuits, :case_id, name: 'idx_sact_case'

    create_table :service_assurance_intervals do |t|
      t.integer :case_id, null: false
      t.integer :circuit_id
      t.string :kind, null: false, default: 'tecnica'
      t.datetime :start_at, null: false
      t.datetime :end_at, null: false
      t.text :note
      t.timestamps
    end
    add_index :service_assurance_intervals, :case_id, name: 'idx_sain_case'
  end

  def down
    remove_index :service_assurance_intervals, name: 'idx_sain_case' if index_exists?(:service_assurance_intervals, nil, name: 'idx_sain_case')
    drop_table :service_assurance_intervals if table_exists?(:service_assurance_intervals)
    remove_index :service_assurance_circuits, name: 'idx_sact_case' if index_exists?(:service_assurance_circuits, nil, name: 'idx_sact_case')
    drop_table :service_assurance_circuits if table_exists?(:service_assurance_circuits)
    remove_index :service_assurance_cases, name: 'idx_sac_assignee' if index_exists?(:service_assurance_cases, nil, name: 'idx_sac_assignee')
    remove_column :service_assurance_cases, :lock_version if column_exists?(:service_assurance_cases, :lock_version)
    remove_column :service_assurance_cases, :original_snapshot if column_exists?(:service_assurance_cases, :original_snapshot)
    remove_column :service_assurance_cases, :assignee_id if column_exists?(:service_assurance_cases, :assignee_id)
    remove_column :service_assurance_evaluations, :lock_version if column_exists?(:service_assurance_evaluations, :lock_version)
  end
end
