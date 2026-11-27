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

    # Compensación pendiente = RECONOCIDO − RECIBIDO (nunca reclamado − recibido).
    # Sin valor reconocido: pendiente de conciliación (jamás cero).
    # received > granted: inconsistencia a revisar.
    def sa_compensation_pending(ev)
      return nil if ev.nil? || ev.credit_granted.nil?
      ev.credit_granted - (ev.compensation_received || 0)
    end

    def sa_compensation_pending_label(ev)
      return 'pendiente de conciliación' if ev.nil? || ev.credit_granted.nil?
      p = sa_compensation_pending(ev)
      return 'revisar (recibido > reconocido)' if p.negative?
      p
    end

    # Diferencia reclamado − reconocido (nilsafe).
    def sa_claim_gap(ev)
      return nil if ev.nil? || ev.credit_requested.nil? || ev.credit_granted.nil?
      ev.credit_requested - ev.credit_granted
    end

    # Estados de reclamación: 4, por envío vs límite, independientes de compensación.
    def sa_claim_status(ev)
      return '—' if ev.nil?
      if ev.sent_on.present?
        return 'enviada_oportuna' if ev.claim_due_on.blank?
        ev.sent_on <= ev.claim_due_on ? 'enviada_oportuna' : 'enviada_fuera_plazo'
      else
        return 'pendiente_envio' if ev.claim_due_on.blank?
        Date.today > ev.claim_due_on ? 'vencida_sin_envio' : 'pendiente_envio'
      end
    end
    def assignee_name(sa_case)
      u = sa_case.assignee
      return '—' if u.nil?
      full = "#{u.firstname} #{u.lastname}".strip
      full.present? ? full : u.login
    rescue StandardError
      '—'
    end

    def full_evaluator(sa_case)
      u = sa_case.assignee
      return '' if u.nil?
      full = "#{u.firstname} #{u.lastname}".strip
      full.present? ? full : u.login.to_s
    rescue StandardError
      ''
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

    # Indisponibilidad legible: 73083 min (1218 h 03 min) o 3 días.
    def sa_downtime_label(minutes)
      m = minutes.to_i
      return '—' if minutes.nil?
      return "#{m} min" if m < 60
      h = m / 60
      return "#{m} min (#{h} h #{format('%02d', m % 60)})" if h < 48
      "#{m} min (#{(h / 24.0).round(1)} días)"
    end
  end
end
