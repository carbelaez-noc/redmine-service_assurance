# frozen_string_literal: true

module FibrazoServiceAssurance
  # Mapa lógico → campo real. Sin IDs en código: ajuste por entorno o
  # autodetección por nombre. Claves: ciudad, inicio, fin, clientes,
  # carrier, caso_isp, categoria, subcategoria, motivo, id_externo.
  module PreloadMap
    DEFAULT_NAMES = {
      'ciudad' => 'Ciudad',
      'inicio' => 'Fecha inicio falla',
      'fin' => 'Fecha fin falla',
      'clientes' => 'Clientes afectados',
      'carrier' => 'Carrier',
      'caso_isp' => '# Caso ISP',
      'categoria' => 'Categoría cierre',
      'subcategoria' => 'Subcategoría cierre',
      'motivo' => 'Motivo cierre',
      'motivo_apertura' => 'Motivo de Apertura',
      'id_externo' => 'ID externo'
    }.freeze

    module_function

    def field_for(key)
      settings = SettingsResolver.settings
      configured = settings["cf_#{key}"].to_s.strip
      if configured.match?(/\A\d+\z/)
        found = IssueCustomField.find_by(id: configured.to_i)
        return found if found
      end
      IssueCustomField.find_by(name: DEFAULT_NAMES[key.to_s])
    end

    def raw_value(issue, key)
      field = field_for(key)
      return [nil, nil] if field.nil?
      cv = issue.custom_value_for(field.id)
      [field, cv&.value]
    end

    # Snapshot de originales { key => {cf_id, raw} } + prefill de evaluación.
    # Nunca escribe al ticket. Distingue ausente (nil) de vacío ('') y cero (0).
    def snapshot(issue)
      snap = {}
      DEFAULT_NAMES.each_key do |key|
        field, raw = raw_value(issue, key)
        snap[key] = { 'cf' => field&.id, 'raw' => raw }
      end
      snap
    end

    def prefill(issue)
      out = {}
      _f, ciudad = raw_value(issue, 'ciudad')
      _f, inicio = raw_value(issue, 'inicio')
      _f, fin = raw_value(issue, 'fin')
      _f, clientes = raw_value(issue, 'clientes')
      _f, carrier = raw_value(issue, 'carrier')
      _f, caso = raw_value(issue, 'caso_isp')
      out[:provider] = carrier.presence
      out[:external_case] = caso.presence
      out[:real_start_at] = inicio.presence
      out[:real_end_at] = fin.presence
      out[:contract_start_at] = inicio.presence
      out[:contract_end_at] = fin.presence
      out[:affected_customers] = clientes.presence
      out
    end

    def display(raw)
      return '— (sin dato)' if raw.nil?
      return '— (vacío)' if raw.to_s.strip.empty?
      raw.to_s
    end
  end
end
