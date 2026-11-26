# frozen_string_literal: true

class ServiceAssuranceCase < ActiveRecord::Base
  STATUSES = %w[pendiente en_revision por_conciliar conciliado no_aplica].freeze

  belongs_to :issue
  belongs_to :assignee, class_name: 'User', foreign_key: 'assignee_id', optional: true
  has_one :evaluation, class_name: 'ServiceAssuranceEvaluation', foreign_key: 'case_id', dependent: :destroy
  has_many :circuits, class_name: 'ServiceAssuranceCircuit', foreign_key: 'case_id', dependent: :destroy
  has_many :intervals, class_name: 'ServiceAssuranceInterval', foreign_key: 'case_id', dependent: :destroy
  has_many :audits, class_name: 'ServiceAssuranceAudit', foreign_key: 'case_id', dependent: :destroy

  validates :issue_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(s) { where(status: s) if STATUSES.include?(s.to_s) }

  serialize :original_snapshot, coder: JSON

  # Idempotente: un issue => máximo un caso. Reaperturas o cambios del CF
  # nunca duplican ni borran la evaluación existente.
  def self.for_issue!(issue)
    FibrazoServiceAssurance::Eligibility.check!(issue)
    record = find_or_initialize_by(issue_id: issue.id)
    is_new = record.new_record?
    record.status ||= 'pendiente'
    record.last_activation_value = issue_activation_snapshot(issue)
    record.last_issue_closed_on ||= issue.closed_on
    if is_new
      record.original_snapshot = FibrazoServiceAssurance::PreloadMap.snapshot(issue)
      record.save!
      pre = FibrazoServiceAssurance::PreloadMap.prefill(issue)
      record.create_evaluation!(pre.compact.presence || {})
      ServiceAssuranceAudit.log(record.id, User.current&.id, 'create', nil, nil)
    else
      record.save! if record.changed?
    end
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

  def age_days
    base = last_issue_closed_on || created_at
    return nil if base.nil?
    ((Time.zone.now - base) / 86_400).to_i
  end
end
