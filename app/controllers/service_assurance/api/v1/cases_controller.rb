# frozen_string_literal: true

module ServiceAssurance
  module Api
    module V1
      # Lectura futura para OneView. Deshabilitada por defecto (ajuste api_read_enabled).
      class CasesController < ApplicationController
        before_action :require_login
        accept_api_auth :index, :show

        def index
          render_403 and return unless FibrazoServiceAssurance::SettingsResolver.settings['api_read_enabled'] == '1'
          cases = ServiceAssuranceCase.order(id: :desc).limit(50)
          render json: { cases: cases.map { |c| { id: c.id, issue_id: c.issue_id, status: c.status } } }
        end

        def show
          render_403 and return unless FibrazoServiceAssurance::SettingsResolver.settings['api_read_enabled'] == '1'
          c = ServiceAssuranceCase.find(params[:id])
          render json: { id: c.id, issue_id: c.issue_id, status: c.status }
        end
      end
    end
  end
end
