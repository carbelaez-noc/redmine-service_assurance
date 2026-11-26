# frozen_string_literal: true

class CreateServiceAssuranceTables < ActiveRecord::Migration[6.1]
  def up
    create_table :service_assurance_cases do |t|
      t.integer :issue_id, null: false
      t.string :status, null: false, default: 'pendiente'
      t.string :last_activation_value
      t.datetime :last_issue_closed_on
      t.timestamps
    end
    add_index :service_assurance_cases, :issue_id, unique: true, name: 'idx_sac_issue_unique'
    add_index :service_assurance_cases, :status, name: 'idx_sac_status'

    create_table :service_assurance_evaluations do |t|
      t.integer :case_id, null: false
      t.string :provider
      t.string :circuit
      t.string :external_case
      t.string :external_verified, default: 'pendiente'
      t.string :impact_type
      t.datetime :real_start_at
      t.datetime :real_end_at
      t.integer :affected_customers
      t.text :observations
      t.boolean :ans_applies
      t.date :reported_on
      t.datetime :contract_start_at
      t.datetime :contract_end_at
      t.text :exclusions
      t.integer :downtime_minutes
      t.boolean :conciliation_applies
      t.date :sent_on
      t.integer :acknowledged_minutes
      t.integer :difference_minutes
      t.text :conciliation_notes
      t.string :result
      t.decimal :credit_requested, precision: 14, scale: 2
      t.decimal :credit_granted, precision: 14, scale: 2
      t.timestamps
    end
    add_index :service_assurance_evaluations, :case_id, unique: true, name: 'idx_sae_case_unique'

    create_table :service_assurance_audits do |t|
      t.integer :case_id
      t.integer :user_id
      t.string :action, null: false
      t.string :field_name
      t.text :old_value
      t.text :new_value
      t.timestamps
    end
    add_index :service_assurance_audits, :case_id, name: 'idx_saa_case'
    add_index :service_assurance_audits, :created_at, name: 'idx_saa_created'
  end

  def down
    remove_index :service_assurance_audits, name: 'idx_saa_created' if index_exists?(:service_assurance_audits, nil, name: 'idx_saa_created')
    remove_index :service_assurance_audits, name: 'idx_saa_case' if index_exists?(:service_assurance_audits, nil, name: 'idx_saa_case')
    drop_table :service_assurance_audits if table_exists?(:service_assurance_audits)
    remove_index :service_assurance_evaluations, name: 'idx_sae_case_unique' if index_exists?(:service_assurance_evaluations, nil, name: 'idx_sae_case_unique')
    drop_table :service_assurance_evaluations if table_exists?(:service_assurance_evaluations)
    remove_index :service_assurance_cases, name: 'idx_sac_status' if index_exists?(:service_assurance_cases, nil, name: 'idx_sac_status')
    remove_index :service_assurance_cases, name: 'idx_sac_issue_unique' if index_exists?(:service_assurance_cases, nil, name: 'idx_sac_issue_unique')
    drop_table :service_assurance_cases if table_exists?(:service_assurance_cases)
  end
end
