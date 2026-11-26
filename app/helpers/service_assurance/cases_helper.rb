# frozen_string_literal: true

module ServiceAssurance
  module CasesHelper
    # Folio corporativo (IMS0003775) cuando el plugin issue_id está presente.
    def issue_folio(issue)
      folio = issue.respond_to?(:issue_id) ? issue.issue_id.to_s : nil
      folio.presence || "##{issue.id}"
    rescue StandardError
      "##{issue.id}"
    end
  end
end
