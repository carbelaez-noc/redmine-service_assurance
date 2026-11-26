# frozen_string_literal: true

class ServiceAssuranceEvaluation < ActiveRecord::Base
  belongs_to :assurance_case, class_name: 'ServiceAssuranceCase', foreign_key: 'case_id'

  validates :case_id, presence: true, uniqueness: true

  # Cálculos autoritativos (el JS solo previsualiza): indisponibilidad =
  # rango a objetar; diferencia = computable − reconocido; ANS Sí =>
  # conciliación automática. Retorna {campo => [antes, después]}.
  def recompute_derived!
    diffs = {}
    if contract_start_at && contract_end_at
      auto = ((contract_end_at - contract_start_at) / 60).to_i
      if downtime_minutes != auto
        diffs['downtime_minutes'] = [downtime_minutes, auto]
        self.downtime_minutes = auto
      end
    end
    if !downtime_minutes.nil? && !acknowledged_minutes.nil?
      auto = downtime_minutes - acknowledged_minutes
      if difference_minutes != auto
        diffs['difference_minutes'] = [difference_minutes, auto]
        self.difference_minutes = auto
      end
    end
    unless ans_applies.nil?
      want = ans_applies ? true : false
      if conciliation_applies != want
        diffs['conciliation_applies'] = [conciliation_applies, want]
        self.conciliation_applies = want
      end
    end
    diffs
  end
end
