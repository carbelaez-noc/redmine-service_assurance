# frozen_string_literal: true

require_relative 'settings_resolver'
require_relative 'preload_map'
require_relative 'eligibility'
require_relative 'carrier_xlsx'
require_relative 'netbox_client'
require_relative 'netbox_sync'

module FibrazoServiceAssurance
  class Engine < ::Rails::Engine
    engine_name :fibrazo_service_assurance
    config.eager_load_paths += Dir["#{config.root}/app/models"]
  end
end
