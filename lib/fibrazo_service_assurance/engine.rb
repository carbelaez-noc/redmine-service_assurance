# frozen_string_literal: true

require_relative 'settings_resolver'
require_relative 'preload_map'
require_relative 'eligibility'
require_relative 'carrier_xlsx'
require_relative 'netbox_client'
require_relative 'netbox_token_store'
require_relative 'netbox_sync'

module FibrazoServiceAssurance
  class Engine < ::Rails::Engine
    engine_name :fibrazo_service_assurance
    config.eager_load_paths += Dir["#{config.root}/app/models"]

    # Rellena SOLO claves ausentes con los defaults del plugin.
    # Nunca sobrescribe valores existentes (nómina, CF, carriers, token).
    # En to_prepare: corre tras el registro de plugins (el initializer temprano no los ve).
    config.to_prepare do
      begin
        unless defined?($sa_settings_defaults_done) && $sa_settings_defaults_done
          plugin = Redmine::Plugin.all.detect { |x| x.id == :fibrazo_service_assurance }
          defaults = plugin && plugin.settings && plugin.settings[:default] || {}
          stored = Setting.plugin_fibrazo_service_assurance
          missing = defaults.keys.map(&:to_s) - stored.keys.map(&:to_s)
          unless missing.empty?
            merged = stored.stringify_keys.merge(defaults.stringify_keys.slice(*missing))
            Setting.plugin_fibrazo_service_assurance = merged
            Rails.logger.info("ServiceAssurance: defaults aplicados a #{missing.inspect}")
          end
          $sa_settings_defaults_done = true
        end
      rescue StandardError => e
        Rails.logger.warn("ServiceAssurance: no se aplicaron defaults (#{e.message})")
      end
    end
  end
end
