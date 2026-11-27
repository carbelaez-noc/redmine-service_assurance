# frozen_string_literal: true

# Validación mensual del comité por proveedor+periodo (identificador).
# Guarda foto de resultados; si una evaluación ya validada cambia,
# needs_review se marca sin borrar el historial.
class ServiceAssuranceMonthlyClosure < ActiveRecord::Base
  self.table_name = 'service_assurance_monthly_closures'

  validates :provider, :periodo, presence: true
  validates :provider, uniqueness: { scope: :periodo }
  validates :periodo, format: { with: /\A\d{4}-(0[1-9]|1[0-2])\z/, message: 'formato YYYY-MM' }
end
