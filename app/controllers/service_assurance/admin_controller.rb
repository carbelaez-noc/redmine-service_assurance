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
      @ans_targets = ServiceAssuranceAnsTarget.order(:provider, :nb_circuit_id, :vigencia_ini)
      @closures = ServiceAssuranceMonthlyClosure.order(periodo: :desc).limit(24)
      @carriers = (ServiceAssuranceNetboxCircuit.distinct.pluck(:provider_name).compact | Setting.plugin_fibrazo_service_assurance['carrier_list'].to_s.lines.map(&:strip)).reject(&:empty?).uniq.sort
    end

    # CRUD mínimo de objetivos ANS: crear y retirar (sin editar historia: retirar + crear nuevo).
    def ans_target_create
      t = ServiceAssuranceAnsTarget.new(ans_target_params)
      if t.save
        flash[:notice] = 'Objetivo ANS registrado'
      else
        flash[:error] = t.errors.full_messages.join('; ')
      end
      redirect_to '/service_assurance/admin'
    end

    def ans_target_retire
      t = ServiceAssuranceAnsTarget.find(params[:id])
      t.update!(estado: 'retirada')
      flash[:notice] = 'Objetivo retirado (histórico preservado)'
      redirect_to '/service_assurance/admin'
    end

    # Validación mensual por proveedor+periodo con foto de resultados.
    def monthly_validate
      provider = params[:provider].to_s.strip
      periodo = params[:periodo].to_s.strip
      unless provider.present? && periodo.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
        flash[:error] = 'Proveedor y periodo YYYY-MM requeridos'
        return redirect_to '/service_assurance/admin'
      end
      y, m = periodo.split('-').map(&:to_i)
      from = Date.new(y, m, 1)
      to = from.end_of_month
      scope = ServiceAssuranceCase.joins(:evaluation).where(service_assurance_evaluations: { provider: provider })
      cases = scope.select { |sa| (d = (sa.evaluation.contract_end_at || sa.evaluation.real_end_at)) && d.to_date >= from && d.to_date <= to }
      snap = { 'casos' => cases.size,
               'conciliados' => cases.count { |sa| sa.status == 'conciliado' },
               'min_objetados' => cases.sum { |sa| sa.evaluation.downtime_minutes.to_i },
               'min_reconocidos' => cases.sum { |sa| sa.evaluation.acknowledged_minutes.to_i } }
      cl = ServiceAssuranceMonthlyClosure.find_or_initialize_by(provider: provider, periodo: periodo)
      cl.update!(validated_by: User.current.id, validated_at: Time.zone.now,
                 notes: params[:notes].to_s.strip.presence, result_snapshot_json: snap.to_json, needs_review: false)
      flash[:notice] = "Mes #{periodo} validado para #{provider}"
      redirect_to '/service_assurance/admin'
    end

    private

    def ans_target_params
      params.require(:target).permit(:nb_circuit_id, :manual_ref, :provider, :service_type, :objetivo, :vigencia_ini, :vigencia_fin, :ref_contractual, :estado)
    end
  end
end
