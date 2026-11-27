# frozen_string_literal: true

class AddServiceIdToEvaluations < ActiveRecord::Migration[6.1]
  def up
    add_column :service_assurance_evaluations, :service_id, :string unless column_exists?(:service_assurance_evaluations, :service_id)
  end

  def down
    remove_column :service_assurance_evaluations, :service_id if column_exists?(:service_assurance_evaluations, :service_id)
  end
end
