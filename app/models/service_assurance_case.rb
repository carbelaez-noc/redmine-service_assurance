# frozen_string_literal: true

class ServiceAssuranceCase < ActiveRecord::Base
  STATUSES = %w[pendiente en_revision por_conciliar conciliado no_aplica].freeze

  belongs_to :issue
  has_one :evaluation, class_name: 'ServiceAssuranceEvaluation', foreign_key: 'case_id', dependent: :destroy
  has_many :audits, class_name: 'ServiceAssuranceAudit', foreign_key: 'case_id', dependent: :destroy

  validates :issue_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(s) { where(status: s) if STATUSES.include?(s.to_s) }

  # Idempotente: un issue => máximo un caso. Reaperturas o cambios del CF
  # nunca duplican ni borran la evaluación existente.
  def self.for_issue!(issue)
    FibrazoServiceAssurance::Eligibility.check!(issue)
    record = find_or_initialize_by(issue_id: issue.id)
    is_new = record.new_record?
    record.status ||= 'pendiente'
    record.last_activation_value = issue_activation_snapshot(issue)
    record.last_issue_closed_on ||= issue.closed_on
    record.save!
    ServiceAssuranceAudit.log(record.id, User.current&.id, is_new ? 'create' : 'open', nil, nil) if is_new
    record
  rescue FibrazoServiceAssurance::Eligibility::OutOfScopeError
    raise
  end

  def self.issue_activation_snapshot(issue)
    field = FibrazoServiceAssurance::SettingsResolver.activation_field
    return nil if field.nil?
    cv = issue.custom_value_for(field.id)
    cv&.value.to_s
  end

  def final?
    %w[conciliado no_aplica].include?(status)
  end
end
