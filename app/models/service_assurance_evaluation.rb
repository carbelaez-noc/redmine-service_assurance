# frozen_string_literal: true

class ServiceAssuranceEvaluation < ActiveRecord::Base
  belongs_to :assurance_case, class_name: 'ServiceAssuranceCase', foreign_key: 'case_id'

  validates :case_id, presence: true, uniqueness: true
end
