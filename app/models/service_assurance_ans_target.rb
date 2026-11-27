# frozen_string_literal: true

# Objetivo ANS por circuito con vigencias históricas.
# Sin UNIQUE absoluto: se permiten varias vigencias por circuito, pero NUNCA
# dos objetivos confirmados superpuestos. Sin fila confirmada, el servicio
# muestra "pendiente" y jamás se usa como objetivo.
class ServiceAssuranceAnsTarget < ActiveRecord::Base
  self.table_name = 'service_assurance_ans_targets'

  ESTADOS = %w[pendiente confirmada retirada].freeze

  validates :estado, inclusion: { in: ESTADOS }
  validates :objetivo, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validate :no_overlap_when_confirmed

  scope :vigente_en, ->(date) { where('vigencia_ini IS NULL OR vigencia_ini <= ?', date).where('vigencia_fin IS NULL OR vigencia_fin >= ?', date) }

  def self.for_circuit(nb_id, manual_ref, date = Date.today)
    scope = where(estado: 'confirmada').vigente_en(date)
    if nb_id.present?
      hit = scope.where(nb_circuit_id: nb_id).order(vigencia_ini: :desc).first
      return hit if hit
    end
    return nil if manual_ref.to_s.strip.empty?
    scope.where(manual_ref: manual_ref.to_s.strip).order(vigencia_ini: :desc).first
  end

  private

  def no_overlap_when_confirmed
    return unless estado == 'confirmada'
    rel = self.class.where(estado: 'confirmada').where.not(id: id)
    if nb_circuit_id.present?
      rel = rel.where(nb_circuit_id: nb_circuit_id)
    elsif manual_ref.to_s.strip.present?
      rel = rel.where(nb_circuit_id: nil, manual_ref: manual_ref.to_s.strip)
    else
      errors.add(:base, 'confirmada requiere circuito NetBox o referencia manual')
      return
    end
    ini = vigencia_ini || Date.new(2000, 1, 1)
    fin = vigencia_fin || Date.new(2100, 12, 31)
    clash = rel.to_a.any? do |o|
      o_ini = o.vigencia_ini || Date.new(2000, 1, 1)
      o_fin = o.vigencia_fin || Date.new(2100, 12, 31)
      ini <= o_fin && o_ini <= fin
    end
    errors.add(:base, 'ya existe un objetivo confirmado superpuesto para este circuito') if clash
  end
end
