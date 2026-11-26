# frozen_string_literal: true

class ServiceAssuranceInterval < ActiveRecord::Base
  self.table_name = 'service_assurance_intervals'

  # Degradaciones nunca son indisponibilidad computable.
  COMPUTABLE_KINDS = %w[tecnica].freeze
  KINDS = %w[tecnica degradacion exclusion contractual reconocida].freeze

  belongs_to :assurance_case, class_name: 'ServiceAssuranceCase', foreign_key: 'case_id'
  belongs_to :circuit, class_name: 'ServiceAssuranceCircuit', foreign_key: 'circuit_id', optional: true

  validates :case_id, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :start_at, presence: true
  validates :end_at, presence: true
  validate :ordered

  def ordered
    return if start_at.blank? || end_at.blank?
    errors.add(:end_at, 'debe ser posterior al inicio') if end_at <= start_at
  end

  def minutes
    return 0 if start_at.blank? || end_at.blank?
    ((end_at - start_at) / 60).to_i
  end

  # Sugerido = técnica − exclusiones. Degradación y reconocida no suman.
  def self.suggested_downtime(case_id)
    rows = where(case_id: case_id).to_a
    tech = rows.select { |r| r.kind == 'tecnica' }.sum(&:minutes)
    excl = rows.select { |r| r.kind == 'exclusion' }.sum(&:minutes)
    [tech - excl, 0].max
  end
end
