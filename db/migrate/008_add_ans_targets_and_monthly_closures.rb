# frozen_string_literal: true

class AddAnsTargetsAndMonthlyClosures < ActiveRecord::Migration[6.1]
  def up
    create_table :service_assurance_ans_targets do |t|
      t.integer :nb_circuit_id
      t.string :manual_ref
      t.string :provider
      t.string :service_type
      t.decimal :objetivo, precision: 5, scale: 2
      t.date :vigencia_ini
      t.date :vigencia_fin
      t.string :ref_contractual
      t.string :estado, default: 'pendiente', null: false
      t.timestamps
    end
    add_index :service_assurance_ans_targets, %i[nb_circuit_id manual_ref provider], name: 'idx_saat_lookup'

    create_table :service_assurance_monthly_closures do |t|
      t.string :provider, null: false
      t.string :periodo, null: false
      t.integer :validated_by
      t.datetime :validated_at
      t.text :notes
      t.text :result_snapshot_json
      t.boolean :needs_review, default: false, null: false
      t.timestamps
    end
    add_index :service_assurance_monthly_closures, %i[provider periodo], unique: true, name: 'idx_samc_provider_periodo'
  end

  def down
    remove_index :service_assurance_monthly_closures, name: 'idx_samc_provider_periodo' if index_exists?(:service_assurance_monthly_closures, nil, name: 'idx_samc_provider_periodo')
    drop_table :service_assurance_monthly_closures if table_exists?(:service_assurance_monthly_closures)
    remove_index :service_assurance_ans_targets, name: 'idx_saat_lookup' if index_exists?(:service_assurance_ans_targets, nil, name: 'idx_saat_lookup')
    drop_table :service_assurance_ans_targets if table_exists?(:service_assurance_ans_targets)
  end
end
