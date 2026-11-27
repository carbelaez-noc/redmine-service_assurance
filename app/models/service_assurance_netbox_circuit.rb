# frozen_string_literal: true

class ServiceAssuranceNetboxCircuit < ActiveRecord::Base
  self.table_name = 'service_assurance_netbox_circuits'

  validates :nb_id, presence: true, uniqueness: true

  scope :active_inventory, -> { where(in_inventory: true) }
  scope :by_provider, ->(name) { where(provider_name: name) if name.present? }

  # Mbps cuando commit_rate viene en Kbps (unidad NetBox). nil si desconocido: nunca 0 inventado.
  def commit_mbps
    return nil if commit_rate_raw.nil?
    return nil unless capacity_unit.to_s == 'Kbps'
    commit_rate_raw / 1000
  end

  def capacity_label
    return 'Sin capacidad registrada' if commit_rate_raw.nil?
    "#{commit_mbps} Mbps (registrada en NetBox)"
  end

  # Componentes individuales de CIDs compuestos ("A // B", espacios).
  def cid_components
    cid_original.to_s.split(%r{\s*//\s*|\s+}).map(&:strip).reject(&:empty?).uniq
  end

  def matches?(query)
    parts = query.to_s.downcase.split.reject(&:empty?)
    return true if parts.empty?
    hay = [cid_original, description, provider_name, cid_components.join(' ')].compact.join(' ').downcase
    parts.all? { |part| hay.include?(part) }
  end
end
