# frozen_string_literal: true

class ServiceAssuranceCircuit < ActiveRecord::Base
  self.table_name = 'service_assurance_circuits'

  belongs_to :assurance_case, class_name: 'ServiceAssuranceCase', foreign_key: 'case_id'

  validates :case_id, presence: true
  validates :circuit, presence: true
end
