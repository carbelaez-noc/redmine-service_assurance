# frozen_string_literal: true

class AddAffectedCapacityToCircuits < ActiveRecord::Migration[6.1]
  def up
    add_column :service_assurance_circuits, :affected_capacity, :string unless column_exists?(:service_assurance_circuits, :affected_capacity)
  end

  def down
    remove_column :service_assurance_circuits, :affected_capacity if column_exists?(:service_assurance_circuits, :affected_capacity)
  end
end
