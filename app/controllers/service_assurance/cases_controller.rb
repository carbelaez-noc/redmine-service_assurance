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

      if field
        norm = yes.map { |v| ActiveRecord::Base.connection.quote(v) }.join(',')
        # Normaliza tildes/comillas en SQL para SÍ/SI/YES sin full-scan adicional:
        # el join ya filtra por custom_field_id (índice) y estado cerrado.
        scope = scope.joins("INNER JOIN custom_values cv_sa ON cv_sa.customized_id = issues.id AND cv_sa.customized_type = 'Issue' AND cv_sa.custom_field_id = #{field.id.to_i}")
                     .where("UPPER(TRIM(BOTH '\"' FROM cv_sa.value)) IN (#{norm})")
      else
        scope = scope.none
      end

      @total = scope.count
      @issues = scope.order('issues.closed_on DESC').limit(100).offset(params[:offset].to_i)
      @case_by_issue = ServiceAssuranceCase.where(issue_id: @issues.map(&:id)).index_by(&:issue_id)
    end

    def show
      @evaluation = @sa_case.evaluation || @sa_case.build_evaluation
      @issue = @sa_case.issue
      @audits = @sa_case.audits.order(id: :desc).limit(50)
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
          render :show and return
        end
        if @sa_case.final? && !allowed?(:reopen_service_assurance)
          flash.now[:error] = 'Evaluación finalizada: requiere permiso de reapertura'
          render :show and return
        end
        changed << %w[status] + [@sa_case.status, status] if @sa_case.status != status
        @sa_case.status = status
      end
      ActiveRecord::Base.transaction do
        @evaluation.save!
        @sa_case.save!
        changed.each { |f, o, n| ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'update', f, [o, n]) }
      end
      flash[:notice] = 'Avance guardado'
      redirect_to service_assurance_case_path(@sa_case)
    end

    def conciliate
      authorize_modify(:manage_conciliations)
      @sa_case.update!(status: 'por_conciliar')
      ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'conciliate', 'status', nil)
      redirect_to service_assurance_case_path(@sa_case)
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
