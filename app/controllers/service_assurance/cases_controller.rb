# frozen_string_literal: true

module ServiceAssurance
  class CasesController < ApplicationController
    before_action :require_login
    before_action :find_case, only: %i[show update evaluate conciliate reopen]
    before_action :authorize_view, only: %i[index show]
    before_action :authorize_modify, only: %i[update evaluate conciliate]
    before_action :authorize_open, only: %i[open]

    helper :issues
    helper ServiceAssurance::CasesHelper
    include ServiceAssurance::CasesHelper

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
      # Casos SA y evaluación para filtros de estado/carrier/evaluador.
      scope = scope.joins('LEFT JOIN service_assurance_cases sac ON sac.issue_id = issues.id')
                   .joins('LEFT JOIN service_assurance_evaluations sae ON sae.case_id = sac.id')
      if @status_filter
        scope = scope.where('sac.status = ?', @status_filter)
      else
        # Por defecto: pendientes por evaluar + evaluados sin cierre.
        scope = scope.where("sac.status IS NULL OR sac.status IN ('pendiente','en_revision','por_conciliar')")
      end
      scope = scope.where('sae.provider ILIKE ?', "%#{@carrier_filter}%") if @carrier_filter.present?
      scope = scope.where('sac.assignee_id = ?', @eval_filter.to_i) if @eval_filter.match?(/\A\d+\z/)

      scope = scope.includes(:project, :status)
      @issue_count = scope.count
      @limit = per_page_option
      @paginator = Paginator.new(@issue_count, @limit, params['page'])
      @issues = scope.order('issues.closed_on DESC').limit(@limit).offset(@paginator.offset).to_a
      cases = ServiceAssuranceCase.where(issue_id: @issues.map(&:id)).includes(:evaluation, :assignee).to_a
      @case_by_issue = cases.index_by(&:issue_id)
      evaluated = ServiceAssuranceEvaluation.where.not(provider: [nil, '']).distinct.pluck(:provider).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      @carrier_options = (FibrazoServiceAssurance::SettingsResolver.carrier_options | evaluated).first(200)
      assignee_ids = ServiceAssuranceCase.where.not(assignee_id: nil).distinct.pluck(:assignee_id)
      @evaluator_options = User.where(id: assignee_ids).order(:firstname).map do |u|
        full = "#{u.firstname} #{u.lastname}".strip
        [full.present? ? full : u.login, u.id]
      end
    end

    def show
      @evaluation = @sa_case.evaluation || @sa_case.build_evaluation
      @issue = @sa_case.issue
      @audits = @sa_case.audits.order(id: :desc).limit(50)
      @attachments = @issue.attachments.to_a
      @carriers = FibrazoServiceAssurance::SettingsResolver.carrier_options
      @carriers |= [@evaluation.provider.to_s.strip] if @evaluation.provider.present?
      @tab_states = FibrazoServiceAssurance::SettingsResolver.tab_states(@sa_case, @evaluation)
      @can_conciliate = allowed?(:manage_conciliations)
      @can_reopen = allowed?(:reopen_service_assurance)
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

    # Flujo por botones (sin selector manual de estado):
    # save (guardar avance) / to_review (en revisión) / to_conciliate (por conciliar, permiso
    # conciliación) / close_accepted|close_rejected (conciliado + motivo, permiso conciliación)
    # / discard (no aplica). Cálculos autoritativos en servidor (JS solo previsualiza).
    TRANSITIONS = {
      'to_review' => 'en_revision',
      'to_conciliate' => 'por_conciliar',
      'close_accepted' => 'conciliado',
      'close_rejected' => 'conciliado',
      'discard' => 'no_aplica'
    }.freeze

    # Flujo lineal: pendiente va directo a conciliación (sin revisión intermedia).
    TRANSITION_FLOW = {
      'pendiente' => %w[save to_conciliate discard],
      'en_revision' => %w[save to_conciliate discard],
      'por_conciliar' => %w[save close_accepted close_rejected],
      'conciliado' => [],
      'no_aplica' => []
    }.freeze

    def update
      @evaluation = @sa_case.evaluation || @sa_case.build_evaluation
      attrs = params.key?(:evaluation) ? evaluation_params : {}
      changed = []
      attrs.each do |k, v|
        old = @evaluation.send(k)
        changed << [k, old, v] if old.to_s != v.to_s
      end
      @evaluation.assign_attributes(attrs)
      transition = params[:transition].to_s
      if transition.present? && transition != 'save'
        unless TRANSITIONS.key?(transition)
          return update_fail('Transición inválida')
        end
        unless (TRANSITION_FLOW[@sa_case.status] || []).include?(transition)
          return update_fail("Transición no disponible desde #{@sa_case.status}")
        end
        if %w[to_conciliate close_accepted close_rejected].include?(transition) && !allowed?(:manage_conciliations)
          return update_fail('Requiere permiso de conciliación')
        end
        if @sa_case.final? && !allowed?(:reopen_service_assurance)
          return update_fail('Evaluación finalizada: requiere permiso de reapertura')
        end
        new_status = TRANSITIONS[transition]
        changed << ['status', @sa_case.status, new_status] if @sa_case.status != new_status
        @sa_case.status = new_status
        if transition == 'close_accepted' && @evaluation.result.to_s.strip.empty?
          @evaluation.result = 'reconocida'
          changed << ['result', '', 'reconocida']
        elsif transition == 'close_rejected' && @evaluation.result.to_s.strip.empty?
          @evaluation.result = 'rechazada'
          changed << ['result', '', 'rechazada']
        end
        if transition == 'close_accepted'
          return update_fail('Cierre requiere fecha de reporte / envío') if @evaluation.reported_on.blank?
          return update_fail('Cierre requiere tiempo reconocido') if @evaluation.acknowledged_minutes.nil?
          return update_fail('Cierre requiere motivo / observaciones de la conciliación') if @evaluation.conciliation_notes.to_s.strip.empty?
        end
        if transition == 'close_rejected' && @evaluation.conciliation_notes.to_s.strip.empty?
          return update_fail('Cierre rechazado requiere motivo')
        end
        if transition == 'discard'
          return update_fail('Indique el motivo de no aplica') if @evaluation.conciliation_notes.to_s.strip.empty?
          if !@evaluation.ans_applies.nil? || !@evaluation.conciliation_applies.nil?
            changed << ['ans_applies', @evaluation.ans_applies, nil]
            changed << ['conciliation_applies', @evaluation.conciliation_applies, nil]
            @evaluation.ans_applies = nil
            @evaluation.conciliation_applies = nil
          end
        end
      elsif @sa_case.final? && !allowed?(:reopen_service_assurance)
        return update_fail('Evaluación finalizada: requiere permiso de reapertura')
      end
      if @sa_case.assignee_id.nil?
        @sa_case.assignee_id = User.current.id
        changed << ['assignee', nil, User.current.login]
      end
      # Sin número de escalamiento ni ID de servicio no se avanza (guardar sí permite).
      # Conciliación exige B completa y devuelve TODOS los faltantes de una vez.
      if transition == 'to_conciliate'
        missing = evaluation_missing(@evaluation)
        return update_fail("Faltan campos para enviar a conciliación: #{missing.join(', ')}") if missing.any?
      elsif transition.present? && transition != 'save' && transition != 'discard'
        if @evaluation.external_case.to_s.strip.empty?
          return update_fail('Requiere número de escalamiento al carrier para avanzar')
        end
        if @evaluation.service_id.to_s.strip.empty?
          return update_fail('Requiere ID del servicio para avanzar')
        end
      end
      if @evaluation.real_start_at && @evaluation.real_end_at && @evaluation.real_end_at <= @evaluation.real_start_at
        return update_fail('Fin real debe ser posterior al inicio real')
      end
      if @evaluation.contract_start_at && @evaluation.contract_end_at && @evaluation.contract_end_at <= @evaluation.contract_start_at
        return update_fail('Fin a objetar debe ser posterior al inicio a objetar')
      end
      ticket_start = begin
        Time.zone.parse(@sa_case.original_snapshot.dig('inicio', 'raw').to_s)
      rescue StandardError
        nil
      end
      now = Time.zone.now
      { 'Inicio a objetar' => @evaluation.contract_start_at,
        'Fin a objetar' => @evaluation.contract_end_at }.each do |label, val|
        next if val.blank?
        return update_fail("#{label}: no puede ser fecha futura") if val > now
        return update_fail("#{label}: anterior al inicio de la falla") if ticket_start && val < ticket_start
      end
      # Autoritativos en servidor (el JS solo previsualiza).
      @evaluation.recompute_derived!.each { |f, (o, n)| changed << [f, o, n] }
      ActiveRecord::Base.transaction do
        @evaluation.save!
        @sa_case.save!
        if !@sa_case.final?
          rec_by_ix = reconcile_circuits!(params[:circuit_links], changed)
          save_circuit_intervals!(params[:circuit_intervals], rec_by_ix, changed) if params.key?(:circuit_intervals)
        end
        changed.each { |f, o, n| ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'update', f, [o, n]) }
      end
      if request.xhr?
        render json: { ok: true, status: @sa_case.status, saved_at: Time.zone.now.strftime('%H:%M:%S'),
                       lock_version: @evaluation.lock_version,
                       downtime: @evaluation.downtime_minutes, difference: @evaluation.difference_minutes,
                       tab_states: FibrazoServiceAssurance::SettingsResolver.tab_states(@sa_case, @evaluation) }
        return
      end
      flash[:notice] = 'Avance guardado'
      redirect_to service_assurance_case_path(@sa_case)
    rescue CircuitError => e
      update_fail(e.message)
    rescue ActiveRecord::StaleObjectError
      update_fail('Otro evaluador guardó cambios mientras editaba. Recargue y reintente.')
    end

    # Reconcilia circuitos asociados (chips del bloque B). Snapshot al asociar;
    # un cambio posterior en NetBox no altera evaluaciones guardadas.
    def reconcile_circuits!(links, changed)
      raw = links.respond_to?(:to_unsafe_h) ? links.to_unsafe_h : links
      incoming = Array(raw.is_a?(Hash) ? raw.values : raw)
      keep_ids = []
      rec_by_ix = {}
      incoming.each_with_index do |l, ix|
        h = l.respond_to?(:to_unsafe_h) ? l.to_unsafe_h : l.to_h
        nb_id = h['nb_id'].to_s.strip.presence&.to_i
        manual = h['manual_cid'].to_s.strip
        ref = h['carrier_ref'].to_s.strip
        note = h['note'].to_s.strip
        link_id = h['link_id'].to_s.strip.presence&.to_i
        if nb_id
          cache = ServiceAssuranceNetboxCircuit.find_by(nb_id: nb_id)
          raise CircuitError, "Circuito NetBox #{nb_id} no está en caché" if cache.nil?
          snap = { 'nb_id' => cache.nb_id, 'cid' => cache.cid_original, 'provider' => cache.provider_name,
                   'capacity' => cache.capacity_label, 'description' => cache.description,
                   'captured_at' => Time.zone.now.strftime('%Y-%m-%d %H:%M') }
          attrs = { nb_circuit_id: nb_id, circuit: cache.cid_original, source: 'netbox',
                    carrier_ref: ref.presence || cache.cid_original, snapshot_json: snap.to_json, note: note.presence }
        else
          raise CircuitError, 'Referencia manual requiere justificación (nota obligatoria)' if manual.empty? || note.empty?
          snap = { 'manual_cid' => manual, 'carrier_ref' => ref.presence || manual,
                   'pending_validation' => true, 'captured_at' => Time.zone.now.strftime('%Y-%m-%d %H:%M') }
          attrs = { nb_circuit_id: nil, circuit: manual, source: 'manual',
                    carrier_ref: ref.presence || manual, snapshot_json: snap.to_json, note: note }
        end
        rec = link_id ? @sa_case.circuits.find_by(id: link_id) : @sa_case.circuits.find_by(nb_circuit_id: nb_id, circuit: attrs[:circuit])
        if rec
          rec.update!(attrs)
        else
          rec = @sa_case.circuits.create!(attrs)
          changed << ['circuit_add', nil, attrs[:circuit]]
        end
        keep_ids << rec.id
        rec_by_ix[ix.to_s] = rec.id
      end
      removed = @sa_case.circuits.where.not(id: keep_ids)
      removed.each { |r| changed << ['circuit_del', r.circuit, nil] }
      removed.destroy_all
      rec_by_ix
    end

    # Intervalos propios por circuito (tiempos que difieren del general).
    # Solo toca intervalos ligados a circuitos; los generales se preservan.
    def save_circuit_intervals!(raw_intervals, rec_by_ix, changed)
      hash = raw_intervals.respond_to?(:to_unsafe_h) ? raw_intervals.to_unsafe_h : raw_intervals
      hash = {} unless hash.is_a?(Hash)
      errors = []
      touched = []
      hash.each do |ix, rows_raw|
        rec_id = rec_by_ix[ix.to_s]
        next if rec_id.nil?
        rows = parse_rows(rows_raw, %w[kind start_at end_at note], errors)
        return update_fail(errors.first) if errors.any?
        link = @sa_case.circuits.find(rec_id)
        link.intervals.destroy_all
        rows.each do |r|
          link.intervals.create!(case_id: @sa_case.id, kind: r['kind'], start_at: r['start_at'], end_at: r['end_at'], note: r['note'])
        end
        touched << link.id
        changed << ['circuit_times', link.carrier_ref, "#{rows.size} intervalo(s)"] if rows.any?
      end
      # Circuitos sin filas enviadas conservan sus intervalos (no se asume nada).
    end

    class CircuitError < StandardError; end

    def update_fail(message)
      if request.xhr?
        render json: { ok: false, error: message }, status: :unprocessable_entity
        return
      end
      flash.now[:error] = message
      render_show
    end

    # Campos obligatorios de B para poder enviar a conciliación.
    def evaluation_missing(ev)
      missing = []
      missing << 'Proveedor' if ev.provider.to_s.strip.empty?
      missing << 'Número de escalamiento carrier' if ev.external_case.to_s.strip.empty?
      missing << 'ID del servicio' if ev.service_id.to_s.strip.empty?
      missing << 'Clientes afectados' if ev.affected_customers.nil?
      missing << '¿Aplica ANS?' if ev.ans_applies.nil?
      missing << 'Fecha de reporte / envío' if ev.reported_on.blank?
      missing << 'Inicio a objetar' if ev.contract_start_at.blank?
      missing << 'Fin a objetar' if ev.contract_end_at.blank?
      missing
    end

    def conciliate
      authorize_modify(:manage_conciliations)
      @sa_case.update!(status: 'por_conciliar')
      ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'conciliate', 'status', nil)
      redirect_to service_assurance_case_path(@sa_case)
    end

    # Búsqueda de circuitos NetBox en caché local (solo lectura).
    def netbox_search
      return render_403 unless allowed?(:view_service_assurance)
      q = params[:q].to_s.strip
      provider = params[:provider].to_s.strip
      scope = ServiceAssuranceNetboxCircuit.where(in_inventory: true).order(:provider_name, :cid_original).limit(200)
      scope = scope.where(provider_name: provider) if provider.present?
      rows = scope.to_a.select { |c| c.matches?(q) }.first(20).map do |c|
        { nb_id: c.nb_id, cid: c.cid_original, provider: c.provider_name,
          capacity: c.capacity_label, type: c.circuit_type, status: c.status,
          description: c.description.presence || '—',
          endpoints: 'Sin información', url: c.url,
          updated: c.nb_updated_at&.strftime('%Y-%m-%d %H:%M') }
      end
      render json: { ok: true, count: rows.size, rows: rows }
    end

    def netbox_sync
      return render_403 unless User.current.admin?
      res = FibrazoServiceAssurance::NetboxSync.run(manual: true)
      flash[res.ok ? :notice : :error] = res.ok ? "NetBox sincronizado: #{res.synced} circuitos" : "Sync NetBox falló: #{res.errors.join('; ')}"
      redirect_to '/settings/plugin/fibrazo_service_assurance'
    end

    # Exporta los casos del periodo en formato de entrega al carrier (XLSX).
    def netbox_token
      return render_403 unless User.current.admin?
      if FibrazoServiceAssurance::NetboxTokenStore.save(params[:token].to_s)
        flash[:notice] = 'Token NetBox guardado cifrado'
      else
        flash[:error] = 'Token vacío: sin cambios'
      end
      redirect_to '/service_assurance/admin'
    end

    def export
      unless allowed?(:view_service_assurance)
        return render_403
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
        snap = sa.original_snapshot || {}
        fmt = ->(v) { v.respond_to?(:strftime) ? v.strftime('%Y-%m-%d %H:%M') : v.to_s }
        [issue&.id, issue_folio(issue), issue&.subject, fmt.call(issue&.closed_on),
         fmt.call(sa.created_at), ev&.provider, ev&.service_id,
         ev&.external_case, ev&.impact_type, fmt.call(snap.dig('inicio', 'raw')),
         fmt.call(snap.dig('fin', 'raw')), fmt.call(ev&.contract_start_at), fmt.call(ev&.contract_end_at),
         ev&.downtime_minutes, ev&.affected_customers,
         ev&.ans_applies.nil? ? '' : (ev.ans_applies ? 'Sí' : 'No'),
         ev&.conciliation_applies.nil? ? '' : (ev.conciliation_applies ? 'Sí' : 'No'),
         ev&.acknowledged_minutes, ev&.difference_minutes, ev&.result,
         ev&.credit_requested, ev&.credit_granted,
         snap.dig('motivo', 'raw').to_s, ev&.conciliation_notes.to_s,
         sa.status, full_evaluator(sa)]
      end
      rows.select! { |r| r[5].to_s.downcase.include?(carrier.downcase) } if carrier.present?
      data = FibrazoServiceAssurance::CarrierXlsx.build(rows)
      send_data data, filename: "service_assurance_#{Date.today.strftime('%Y%m%d')}.xlsx",
                      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    end

    def reopen
      unless allowed?(:reopen_service_assurance)
        return render_403
      end
      @sa_case.update!(status: 'en_revision')
      ServiceAssuranceAudit.log(@sa_case.id, User.current.id, 'reopen', 'status', nil)
      redirect_to service_assurance_case_path(@sa_case)
    end

    private

    def render_show
      @evaluation ||= @sa_case.evaluation || @sa_case.build_evaluation
      @issue = @sa_case.issue
      @audits = @sa_case.audits.order(id: :desc).limit(50)
      @attachments = @issue.attachments.to_a
      @carriers = FibrazoServiceAssurance::SettingsResolver.carrier_options
      @carriers |= [@evaluation.provider.to_s.strip] if @evaluation.provider.present?
      @tab_states = FibrazoServiceAssurance::SettingsResolver.tab_states(@sa_case, @evaluation)
      @can_conciliate = allowed?(:manage_conciliations)
      @can_reopen = allowed?(:reopen_service_assurance)
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
      return redirect_to(service_assurance_path)
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
      # Nómina explícita: si está configurada, solo ellos (+admins) entran al módulo.
      roster = Array(Setting.plugin_fibrazo_service_assurance['allowed_user_ids']).map(&:to_i).reject(&:zero?)
      return roster.include?(User.current.id) if roster.any?
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
      # downtime/difference/conciliation/result: calculados o derivados en servidor, no editables.
      # sent_on/external_verified: retirados del formulario (una sola fecha; sin verificación por ahora).
      params.require(:evaluation).permit(
        :lock_version,
        :provider, :external_case, :service_id, :impact_type,
        :real_start_at, :real_end_at, :affected_customers, :observations,
        :ans_applies, :reported_on, :contract_start_at, :contract_end_at,
        :exclusions,
        :acknowledged_minutes, :conciliation_notes,
        :credit_granted
      )
    end
  end
end
