# frozen_string_literal: true

require 'redmine'
require_relative 'lib/fibrazo_service_assurance/engine'

Redmine::Plugin.register :fibrazo_service_assurance do
  name 'Service Assurance'
  author 'Fibrazo NOC'
  description 'Bandeja ligera de evaluación y conciliación de ANS de proveedores externos. Tablas propias, sin tocar issues.'
  version '0.4.0'
  url 'https://github.com/carbelaez-noc/redmine-service_assurance'
  requires_redmine version_or_higher: '5.0.0'

  settings default: {
    'activation_cf_id' => '',
    'activation_yes_value' => 'SÍ',
    'eligible_tracker_ids' => [],
    'eligible_project_ids' => [],
    'eligible_status_ids' => [],
    'api_read_enabled' => '0',
    'cf_ciudad' => '', 'cf_inicio' => '', 'cf_fin' => '', 'cf_clientes' => '',
    'cf_carrier' => '', 'cf_caso_isp' => '', 'cf_categoria' => '',
    'cf_subcategoria' => '', 'cf_motivo' => '', 'cf_motivo_apertura' => '', 'cf_id_externo' => '',
    'carrier_list' => ''
  }, partial: 'settings/fibrazo_service_assurance_settings'

  project_module :service_assurance do
    permission :view_service_assurance, { 'service_assurance/cases' => %i[index show] }, read: true
    permission :evaluate_service_assurance, { 'service_assurance/cases' => %i[show update evaluate] }, require: :member
    permission :manage_conciliations, { 'service_assurance/cases' => %i[show update conciliate] }, require: :member
    permission :reopen_service_assurance, { 'service_assurance/cases' => %i[reopen] }, require: :member
    permission :admin_service_assurance, { 'service_assurance/admin' => %i[show] }, require: :member
  end

  menu :admin_menu, :service_assurance,
       { controller: 'service_assurance/cases', action: 'index' },
       caption: 'Service Assurance',
       parent: :fibrazo,
       if: Proc.new { User.current.admin? }
end
