# frozen_string_literal: true

class AddClaimFieldsToEvaluations < ActiveRecord::Migration[6.1]
  def up
    add_column :service_assurance_evaluations, :reported_at, :datetime unless column_exists?(:service_assurance_evaluations, :reported_at)
    add_column :service_assurance_evaluations, :claim_due_on, :date unless column_exists?(:service_assurance_evaluations, :claim_due_on)
    add_column :service_assurance_evaluations, :credit_note_ref, :string unless column_exists?(:service_assurance_evaluations, :credit_note_ref)
    add_column :service_assurance_evaluations, :compensation_status, :string, default: 'pendiente' unless column_exists?(:service_assurance_evaluations, :compensation_status)
    add_column :service_assurance_evaluations, :compensation_received, :decimal, precision: 14, scale: 2 unless column_exists?(:service_assurance_evaluations, :compensation_received)
  end

  def down
    %i[reported_at claim_due_on credit_note_ref compensation_status compensation_received].each do |c|
      remove_column :service_assurance_evaluations, c if column_exists?(:service_assurance_evaluations, c)
    end
  end
end
