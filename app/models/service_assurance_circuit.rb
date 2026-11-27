# frozen_string_literal: true

class ServiceAssuranceCircuit < ActiveRecord::Base
  self.table_name = 'service_assurance_circuits'

  belongs_to :assurance_case, class_name: 'ServiceAssuranceCase', foreign_key: 'case_id'

  has_many :intervals, class_name: 'ServiceAssuranceInterval', foreign_key: 'circuit_id', dependent: :destroy

  validates :case_id, presence: true
  validates :circuit, presence: true
end
