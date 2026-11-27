# frozen_string_literal: true

class AddClaimDueSource < ActiveRecord::Migration[6.1]
  def up
    add_column :service_assurance_evaluations, :claim_due_source, :string unless column_exists?(:service_assurance_evaluations, :claim_due_source)
  end

  def down
    remove_column :service_assurance_evaluations, :claim_due_source if column_exists?(:service_assurance_evaluations, :claim_due_source)
  end
end
