# frozen_string_literal: true

module ServiceAssurance
  class AdminController < ApplicationController
    before_action :require_admin

    def show
      s = FibrazoServiceAssurance::SettingsResolver
      @activation_field = s.activation_field
      @yes_values = s.yes_values
      @eligible_status_ids = s.eligible_status_ids
      @eligible_tracker_ids = s.eligible_tracker_ids
      @eligible_project_ids = s.eligible_project_ids
      @case_count = ServiceAssuranceCase.count
      @by_status = ServiceAssuranceCase.group(:status).count
    end
  end
end
