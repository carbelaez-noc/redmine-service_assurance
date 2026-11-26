# frozen_string_literal: true

module ServiceAssurance
  module CasesHelper
    # Folio corporativo (IMS0003775) cuando el plugin issue_id está presente.
    def issue_folio(issue)
      folio = issue.respond_to?(:issue_id) ? issue.issue_id.to_s : nil
      folio.presence || "##{issue.id}"
    rescue StandardError
      "##{issue.id}"
    end

    # Nombre y apellido del evaluador (nunca solo el login).
    def assignee_name(sa_case)
      u = sa_case.assignee
      return '—' if u.nil?
      full = "#{u.firstname} #{u.lastname}".strip
      full.present? ? full : u.login
    rescue StandardError
      '—'
    end

    STATUS_COLORS = {
      'pendiente' => '#8a6d00',
      'en_revision' => '#1f6feb',
      'por_conciliar' => '#9c27b0',
      'conciliado' => '#2e7d32',
      'no_aplica' => '#616161'
    }.freeze

    def sa_status_label(status)
      color = STATUS_COLORS[status.to_s] || '#333'
      "<span style=\"color:#{color};font-weight:600\">#{status}</span>".html_safe
    end
  end
end
