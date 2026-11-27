# frozen_string_literal: true

class ExtendCircuitsForNetbox < ActiveRecord::Migration[6.1]
  def up
    add_column :service_assurance_circuits, :nb_circuit_id, :integer unless column_exists?(:service_assurance_circuits, :nb_circuit_id)
    add_column :service_assurance_circuits, :carrier_ref, :string unless column_exists?(:service_assurance_circuits, :carrier_ref)
    add_column :service_assurance_circuits, :snapshot_json, :text unless column_exists?(:service_assurance_circuits, :snapshot_json)
    add_column :service_assurance_circuits, :source, :string, default: 'manual' unless column_exists?(:service_assurance_circuits, :source)
    add_column :service_assurance_circuits, :note, :text unless column_exists?(:service_assurance_circuits, :note)
    add_index :service_assurance_circuits, %i[case_id nb_circuit_id], name: 'idx_sac_case_nb' unless index_exists?(:service_assurance_circuits, %i[case_id nb_circuit_id], name: 'idx_sac_case_nb')
  end

  def down
    remove_index :service_assurance_circuits, name: 'idx_sac_case_nb' if index_exists?(:service_assurance_circuits, %i[case_id nb_circuit_id], name: 'idx_sac_case_nb')
    %i[nb_circuit_id carrier_ref snapshot_json source note].each do |c|
      remove_column :service_assurance_circuits, c if column_exists?(:service_assurance_circuits, c)
    end
  end
end
