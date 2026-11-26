# frozen_string_literal: true

module ServiceAssurance
  class CasesController < ApplicationController
    before_action :require_login
    before_action :find_case, only: %i[show update evaluate conciliate reopen]
    before_action :authorize_view, only: %i[index show]
    before_action :authorize_modify, only: %i[update evaluate conciliate]
    before_action :authorize_open, only: %i[open]

    helper :issues

    def index
      scope = FibrazoServiceAssurance::SettingsResolver.eligible_scope
      field = FibrazoServiceAssurance::SettingsResolver.activation_field
      yes = FibrazoServiceAssurance::SettingsResolver.yes_values
      @status_filter = params[:sa_status].to_s
      @status_filter = nil unless ServiceAssuranceCase::STATUSES.include?(@status_filter)
      @carrier_filter = params[:sa_carrier].to_s.strip
      @eval_filter = params[:sa_eval].to_s.strip
      @from = params[:sa_from].to_s.strip
      @to = params[:sa_to].to_s.strip

      if field
        norm = yes.map { |v| ActiveRecord::Base.connection.quote(v) }.join(',')
        # Normaliza tildes/comillas/mayúsculas en SQL (SÍ=SI) sin full-scan:
        # el join filtra por custom_field_id (índice) + estado cerrado.
        scope = scope.joins("INNER JOIN custom_values cv_sa ON cv_sa.customized_id = issues.id AND cv_sa.customized_type = 'Issue' AND cv_sa.custom_field_id = #{field.id.to_i}")
                     .where("TRANSLATE(UPPER(TRIM(BOTH '\"' FROM cv_sa.value)), 'ÁÉÍÓÚÜ', 'AEIOU') IN (#{norm})")
      else
        scope = scope.none
      end
      scope = scope.where('issues.closed_on >= ?', Date.parse(@from).beginning_of_day) if @from.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      scope = scope.where('issues.closed_on <= ?', Date.parse(@to).end_of_day) if @to.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      scope = scope.includes(:project, :status)
      @total = scope.count
      @issues = scope.order('issues.closed_on DESC').limit(100).offset(params[:offset].to_i)
      cases = ServiceAssuranceCase.where(issue_id: @issues.map(&:id)).includes(:evaluation, :assignee).to_a
      @case_by_issue = cases.index_by(&:issue_id)
      if @status_filter || @carrier_filter.present? || @eval_filter.present?
        @issues = @issues.to_a.select do |issue|
          sa = @case_by_issue[issue.id]
          next false if @status_filter && sa&.status != @status_filter
          if @carrier_filter.present?
            prov = sa&.evaluation&.provider.to_s.downcase
            next false unless prov.include?(@carrier_filter.downcase)
          end
          if @eval_filter.present?
            next false unless sa&.assignee_id.to_s == @eval_filter
          end
          true
        end
      end
    end

    def show
      @evaluation = @sa_case.evaluation || @sa_case.build_evaluation
      @issue = @sa_case.issue
      @circuits = @sa_case.circuits.order(:id).to_a
      @intervals = @sa_case.intervals.order(:start_at).to_a
      @audits = @sa_case.audits.order(id: :desc).limit(50)
      @journals = @issue.journals.includes(:user).order(:id).to_a.select { |j| j.notes.present? }
      @attachments = @issue.attachments.to_a
      @suggested = ServiceAssuranceInterval.suggested_downtime(@sa_case.id)
      @carriers = FibrazoServiceAssurance::SettingsResolver.carrier_options
      @carriers |= [@evaluation.provider.to_s.strip] if @evaluation.provider.present?
      @tab_states = FibrazoServiceAssurance::SettingsResolver.tab_states(@sa_case, @evaluation)
      @readonly_issue = true
    end

    # Crea (idempotente) el caso desde un issue elegible y redirige al detalle.
    def open
      issue = Issue.find(params[:issue_id])
      sa_case = ServiceAssuranceCase.for_issue!(issue)
      redirect_to service_assurance_case_path(sa_case)
    rescue FibrazoServiceAssurance::Eligibility::OutOfScopeError => e
      flash[:error] = "Fuera de alcance: #{e.message}"
      redirect_to service_assurance_path
    end

    # Abre (crea idempotente) la evaluación desde un issue elegible.
    def evaluate
      redirect_to service_assurance_case_path(@sa_case)
    end

    def update
      @evaluation = @sa_case.evaluation || @sa_case.build_evaluation
      attrs = evaluation_params
      changed = []
      attrs.each do |k, v|
        old = @evaluation.send(k)
        changed << [k, old, v] if old.to_s != v.to_s
      end
      status = params[:sa_status].to_s
      if status.present?
        unless ServiceAssuranceCase::STATUSES.include?(status)
          flash.now[:error] = 'Estado inválido'
          render_show and return
        end
        if @sa_case.final? && @sa_case.status != status && !allowed?(:reopen_service_assurance)
          flash.now[:error] = 'Evaluación finalizada: requiere permiso de reapertura'
          render_show and return
        end
        changed << %w[status] + [@sa_case.status, status] if @sa_case.status != status
        @sa_case.status = status
      end
      if @sa_case.assignee_id.nil?
        @sa_case.assignee_id = User.current.id
        changed << ['assignee', nil, User.current.login]
      end
      parse_errors = []
      new_circuits = parse_rows(params[:circuits], %w[circuit external_case external_verified], parse_errors)
      new_intervals = parse_rows(params[:intervals], %w[kind start_at end_at note circuit_ref], parse_errors)
      if parse_errors.any?
        flash.now[:error] = parse_errors.first(3).join('; ')
        render_show and return
      end
      if @evaluation.real_start_at && @evaluation.real_end_at && @evaluation.real_end_at <= @evaluation.real_start_at
        flash.now[:error] = 'Fin real debe ser posterior al inicio real'
        render_show and return
      end
      if @evaluation.contract_start_at && @evaluation.contract_end_at && @evaluation.contract_end_at <= @evaluation.contract_start_at
        flash.now[:error] = 'Fin contractual debe ser posterior al inicio contractual'
        render_show and return
      end
      ActiveRecord::Base.transaction do
        @evaluation.save!
        @sa_case.save!
        @sa_case.circuits.destroy_all
        @sa_case.intervals.destroy_all
        new_circuits.each { |c| @sa_case.circuits.create!(c) }
        new_intervals.each { |r| @sa_case.intervals.create!(r.except('circuit_ref')) }
        changed.each { |f, o, n| ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'update', f, [o, n]) }
        ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'update', 'circuits/intervals', nil) if new_circuits.any? || new_intervals.any?
      end
      flash[:notice] = 'Avance guardado'
      redirect_to service_assurance_case_path(@sa_case)
    rescue ActiveRecord::StaleObjectError
      flash[:error] = 'Otro evaluador guardó cambios mientras editaba. Recargue y reintente.'
      redirect_to service_assurance_case_path(@sa_case)
    end

    def conciliate
      authorize_modify(:manage_conciliations)
      @sa_case.update!(status: 'por_conciliar')
      ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'conciliate', 'status', nil)
      redirect_to service_assurance_case_path(@sa_case)
    end

    # Exporta los casos del periodo en formato de entrega al carrier (XLSX).
    def export
      unless allowed?(:view_service_assurance)
        render_403 and return
      end
      from = params[:sa_from].to_s.strip
      to = params[:sa_to].to_s.strip
      carrier = params[:sa_carrier].to_s.strip
      cases = ServiceAssuranceCase.includes(:issue, :evaluation, :assignee, :circuits)
      if from.match?(/\A\d{4}-\d{2}-\d{2}\z/) || to.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        cases = cases.joins(:issue)
        cases = cases.where('issues.closed_on >= ?', Date.parse(from).beginning_of_day) if from.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        cases = cases.where('issues.closed_on <= ?', Date.parse(to).end_of_day) if to.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      end
      rows = cases.order(:id).limit(2000).map do |sa|
        ev = sa.evaluation
        issue = sa.issue
        circuits = sa.circuits.any? ? sa.circuits.map(&:circuit).join('; ') : ev&.circuit.to_s
        fmt = ->(v) { v.respond_to?(:strftime) ? v.strftime('%Y-%m-%d %H:%M') : v.to_s }
        [sa.id, issue&.id, issue&.subject, fmt.call(issue&.closed_on), ev&.provider,
         circuits, ev&.external_case, fmt.call(ev&.real_start_at), fmt.call(ev&.real_end_at),
         ev&.downtime_minutes, ev&.affected_customers, ev&.impact_type,
         ev&.ans_applies.nil? ? '' : (ev.ans_applies ? 'Sí' : 'No'),
         ev&.conciliation_applies.nil? ? '' : (ev.conciliation_applies ? 'Sí' : 'No'),
         ev&.acknowledged_minutes, ev&.difference_minutes, ev&.result,
         ev&.credit_requested, ev&.credit_granted, sa.status, sa.assignee&.login]
      end
      rows.select! { |r| r[4].to_s.downcase.include?(carrier.downcase) } if carrier.present?
      data = FibrazoServiceAssurance::CarrierXlsx.build(rows)
      send_data data, filename: "service_assurance_#{Date.today.strftime('%Y%m%d')}.xlsx",
                      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    end

    def reopen
      unless allowed?(:reopen_service_assurance)
        render_403 and return
      end
      @sa_case.update!(status: 'en_revision')
      ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'reopen', 'status', nil)
      redirect_to service_assurance_case_path(@sa_case)
    end

    private

    def render_show
      @issue = @sa_case.issue
      @circuits = @sa_case.circuits.order(:id).to_a
      @intervals = @sa_case.intervals.order(:start_at).to_a
      @audits = @sa_case.audits.order(id: :desc).limit(50)
      @journals = @issue.journals.includes(:user).order(:id).to_a.select { |j| j.notes.present? }
      @attachments = @issue.attachments.to_a
      @suggested = ServiceAssuranceInterval.suggested_downtime(@sa_case.id)
      render :show
    end

    # Filas repetidas `name[][campo]`: llegan como ActionController::Parameters.
    # Filas totalmente vacías se ignoran; el resto se valida servidor.
    def parse_rows(raw, allowed, errors)
      return [] if raw.nil?
      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      rows = hash.is_a?(Hash) ? hash.values : Array(hash)
      out = []
      rows.each_with_index do |row, idx|
        next unless row.is_a?(Hash)
        row = row.slice(*allowed)
        next if row.values.all? { |v| v.to_s.strip.empty? }
        if allowed.include?('circuit') && row['circuit'].to_s.strip.empty?
          errors << "Fila #{idx + 1}: circuito requerido"
          next
        end
        if allowed.include?('kind')
          unless ServiceAssuranceInterval::KINDS.include?(row['kind'].to_s)
            errors << "Fila #{idx + 1}: tipo de intervalo inválido"
            next
          end
          %w[start_at end_at].each do |k|
            begin
              row[k] = Time.zone.parse(row[k].to_s) if row[k].present?
            rescue StandardError
              row[k] = nil
            end
          end
          if row['start_at'].blank? || row['end_at'].blank?
            errors << "Fila #{idx + 1}: inicio y fin requeridos"
            next
          end
          if row['end_at'] <= row['start_at']
            errors << "Fila #{idx + 1}: fin debe ser posterior al inicio"
            next
          end
        end
        out << row
      end
      out
    end

    def find_case
      # POST evaluate puede llegar con issue_id (crea idempotente) o id de caso.
      if params[:issue_id].present?
        issue = Issue.find(params[:issue_id])
        @sa_case = ServiceAssuranceCase.for_issue!(issue)
      else
        @sa_case = ServiceAssuranceCase.find(params[:id])
      end
    rescue FibrazoServiceAssurance::Eligibility::OutOfScopeError => e
      flash[:error] = "Fuera de alcance: #{e.message}"
      redirect_to service_assurance_path and return
    end

    def authorize_view
      deny_unless(allowed?(:view_service_assurance))
    end

    def authorize_open
      deny_unless(allowed?(:evaluate_service_assurance))
    end

    def authorize_modify(action = nil)
      perm = action || (params[:action] == 'conciliate' ? :manage_conciliations : :evaluate_service_assurance)
      deny_unless(allowed?(perm))
    end

    def allowed?(perm)
      return true if User.current.admin?
      project = @sa_case&.issue&.project
      return User.current.allowed_to?(perm, project) if project
      User.current.projects.to_a.any? { |p| User.current.allowed_to?(perm, p) }
    rescue StandardError
      false
    end

    def deny_unless(ok)
      render_403 unless ok
    end

    def evaluation_params
      params.require(:evaluation).permit(
        :lock_version,
        :provider, :circuit, :external_case, :external_verified, :impact_type,
        :real_start_at, :real_end_at, :affected_customers, :observations,
        :ans_applies, :reported_on, :contract_start_at, :contract_end_at,
        :exclusions, :downtime_minutes, :conciliation_applies,
        :sent_on, :acknowledged_minutes, :difference_minutes, :conciliation_notes,
        :result, :credit_requested, :credit_granted
      )
    end
  end
end
