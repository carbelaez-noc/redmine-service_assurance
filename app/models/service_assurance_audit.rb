# frozen_string_literal: true

class ServiceAssuranceAudit < ActiveRecord::Base
  belongs_to :assurance_case, class_name: 'ServiceAssuranceCase', foreign_key: 'case_id', optional: true
  belongs_to :user, optional: true

  validates :action, presence: true

  def self.log(case_id, user_id, action, field_name, old_new)
    old_v, new_v = Array(old_new)
    create!(
      case_id: case_id, user_id: user_id, action: action.to_s,
      field_name: field_name.to_s, old_value: old_v.to_s, new_value: new_v.to_s
    )
  end
end
