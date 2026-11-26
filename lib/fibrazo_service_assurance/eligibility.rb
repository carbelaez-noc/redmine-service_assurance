# frozen_string_literal: true

require_relative 'settings_resolver'

module FibrazoServiceAssurance
  # Entrada única de elegibilidad: trabajos, consola y futuras llamadas pasan por aquí.
  class Eligibility
    class OutOfScopeError < StandardError; end

    def self.reason(issue)
      s = SettingsResolver
      return "estado #{issue.status_id} no elegible" unless s.eligible_status_ids.include?(issue.status_id)
      tids = s.eligible_tracker_ids
      return "tracker #{issue.tracker_id} fuera de alcance" if tids.any? && !tids.include?(issue.tracker_id)
      pids = s.eligible_project_ids
      return "proyecto #{issue.project_id} fuera de alcance" if pids.any? && !pids.include?(issue.project_id)
      return 'campo de activación sin valor afirmativo' unless s.activated?(issue)
      nil
    end

    def self.check!(issue)
      msg = reason(issue)
      raise OutOfScopeError, msg if msg
      true
    end
  end
end
