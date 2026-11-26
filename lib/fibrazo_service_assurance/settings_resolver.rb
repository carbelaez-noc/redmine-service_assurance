# frozen_string_literal: true

module FibrazoServiceAssurance
  # Resuelve configuración sin IDs hardcodeados.
  module SettingsResolver
    module_function

    def settings
      Setting.plugin_fibrazo_service_assurance || {}
    end

    # Campo de activación: id configurado; si vacío, autodetecta por nombre.
    def activation_field
      id = settings['activation_cf_id'].to_s.strip
      return IssueCustomField.find_by(id: id.to_i) if id.match?(/\A\d+\z/)
      IssueCustomField.where(field_format: 'list')
                      .detect { |f| f.name.to_s.strip.downcase == '¿requiere evaluación de ans?' }
    end

    def yes_values
      raw = settings['activation_yes_value'].to_s.strip
      base = raw.empty? ? 'SÍ' : raw
      [base, normalize(base), 'SI', 'SÍ', 'YES', '1'].map { |v| normalize(v) }.uniq
    end

    def normalize(value)
      value.to_s.strip.upcase
           .tr('ÁÉÍÓÚÜ', 'AEIOU')
           .gsub(/\A['"]+|['"]+\z/, '')
    end

    def activated?(issue)
      field = activation_field
      return false if field.nil?
      cv = issue.custom_value_for(field.id)
      return false if cv.nil?
      yes_values.include?(normalize(cv.value.to_s))
    end

    def eligible_status_ids
      ids = Array(settings['eligible_status_ids']).map(&:to_i).reject(&:zero?)
      return ids if ids.any?
      IssueStatus.where(is_closed: true).pluck(:id)
    end

    def eligible_tracker_ids
      Array(settings['eligible_tracker_ids']).map(&:to_i).reject(&:zero?)
    end

    def eligible_project_ids
      Array(settings['eligible_project_ids']).map(&:to_i).reject(&:zero?)
    end

    # Elegible = cerrada + tracker/proyecto en alcance (si se configuró) + activación Sí.
    # Nunca barre todos los tickets: se usa con paginación y filtros del índice.
    def eligible_scope
      scope = Issue.where(status_id: eligible_status_ids)
      scope = scope.where(tracker_id: eligible_tracker_ids) if eligible_tracker_ids.any?
      scope = scope.where(project_id: eligible_project_ids) if eligible_project_ids.any?
      scope
    end

    def list_candidate_fields
      IssueCustomField.where(field_format: 'list').order(:name).pluck(:name, :id)
    end

    # Lista configurable de carriers (uno por línea en el ajuste).
    def carrier_options
      settings['carrier_list'].to_s.lines.map(&:strip).reject(&:empty?).uniq.first(200)
    end

    # Completitud por pestaña para pintar el estado (rojo pastel = incompleta).
    def tab_states(sa_case, evaluation)
      ev = evaluation || ServiceAssuranceEvaluation.new
      b = ev.provider.present? && ev.real_start_at.present? && ev.real_end_at.present? && !ev.affected_customers.nil?
      c = !ev.ans_applies.nil? && ev.reported_on.present? && ev.contract_start_at.present? &&
          ev.contract_end_at.present? && !ev.downtime_minutes.nil? && !ev.conciliation_applies.nil?
      d = d_complete?(ev)
      e = ev.circuit.present? || sa_case.circuits.any? || sa_case.intervals.any?
      { a: true, b: b, c: c, d: d, e: e, f: true }
    end

    def d_complete?(ev)
      return true if ev.conciliation_applies == false
      ev.sent_on.present? && !ev.acknowledged_minutes.nil? &&
        !ev.difference_minutes.nil? && ev.result.present?
    end
  end
end
