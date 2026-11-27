# frozen_string_literal: true

namespace :service_assurance do
  desc 'Sincroniza caché de circuitos NetBox (solo lectura)'
  task netbox_sync: :environment do
    res = FibrazoServiceAssurance::NetboxSync.run
    puts "ok=#{res.ok} synced=#{res.synced} errors=#{res.errors.inspect}"
    exit(res.ok ? 0 : 1)
  end
end
