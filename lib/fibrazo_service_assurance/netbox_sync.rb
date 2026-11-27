# frozen_string_literal: true

module FibrazoServiceAssurance
  # Sincronización solo-lectura NetBox -> caché local. Idempotente por nb_id.
  # Nunca elimina: ante fallo o respuesta parcial conserva el último inventario válido.
  class NetboxSync
    LOCK_KEY = 'fibrazo_sa_netbox_sync_lock'

    Result = Struct.new(:ok, :synced, :errors, :started_at, :finished_at, keyword_init: true)

    def self.settings
      Setting.plugin_fibrazo_service_assurance
    end

    def self.token
      NetboxTokenStore.read
    end

    def self.run(manual: false)
      started = Time.zone.now
      errors = []
      unless acquire_lock
        return finish!(Result.new(ok: false, synced: 0, errors: ['sincronización en curso'], started_at: started, finished_at: Time.zone.now))
      end
      begin
        base = settings['netbox_base_url'].to_s.strip.presence || 'https://nb.fibrazo.com.co'
        client = NetboxClient.new(base_url: base, token: token)
        raise NetboxClient::Error, 'token NetBox no configurado (ruta inválida o ilegible)' if token.nil?
        circuits = client.circuits(limit: 100)
        synced = 0
        seen = []
        circuits.each do |c|
          nb_id = c['id']
          next if nb_id.nil?
          seen << nb_id
          # Solo se escribe si hay cambios reales (sin churn de updated_at).
          data = {
            provider_id: c.dig('provider', 'id'),
            provider_name: c.dig('provider', 'name'),
            cid_original: c['cid'].to_s,
            circuit_type: c.dig('type', 'name'),
            status: c.dig('status', 'value') || c.dig('status', 'label'),
            commit_rate_raw: c['commit_rate'],
            capacity_unit: 'Kbps',
            description: c['description'].to_s,
            endpoints_json: {}.to_json,
            url: c['display_url'] || c['url'],
            nb_updated_at: c['last_updated'],
            in_inventory: true
          }
          rec = ServiceAssuranceNetboxCircuit.find_or_initialize_by(nb_id: nb_id)
          norm = lambda { |k, v|
            v = Time.zone.parse(v.to_s).utc.to_s if k == :nb_updated_at && v.to_s.present?
            v.to_s
          }
          current = data.keys.index_with { |k| norm.call(k, rec.send(k)) }
          fresh = data.keys.index_with { |k| norm.call(k, data[k]) }
          if rec.new_record? || current != fresh
            rec.assign_attributes(data)
            rec.synced_at = Time.zone.now
            rec.save!
          end
          synced += 1
        end
        # Retirados: solo si la descarga fue completa; nunca ante parciales.
        if errors.empty?
          ServiceAssuranceNetboxCircuit.where.not(nb_id: seen).update_all(in_inventory: false) if seen.any?
        end
        finish!(Result.new(ok: true, synced: synced, errors: errors, started_at: started, finished_at: Time.zone.now))
      rescue NetboxClient::Error, ActiveRecord::RecordInvalid => e
        errors << e.message.to_s[0, 200]
        finish!(Result.new(ok: false, synced: 0, errors: errors, started_at: started, finished_at: Time.zone.now))
      ensure
        release_lock
      end
    end

    def self.acquire_lock
      return false if Rails.cache.read(LOCK_KEY)
      Rails.cache.write(LOCK_KEY, Time.zone.now.to_s, expires_in: 15.minutes)
      true
    end

    def self.release_lock
      Rails.cache.delete(LOCK_KEY)
    end

    def self.finish!(result)
      s = settings
      s['netbox_last_sync_at'] = result.finished_at.strftime('%Y-%m-%d %H:%M') if result.ok
      s['netbox_last_result'] = result.ok ? "OK #{result.synced} circuitos" : "FALLO: #{result.errors.join('; ')[0, 200]}"
      s['netbox_last_count'] = ServiceAssuranceNetboxCircuit.where(in_inventory: true).count.to_s
      Setting.plugin_fibrazo_service_assurance = s
      result
    end
  end
end
