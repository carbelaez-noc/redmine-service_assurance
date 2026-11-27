# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  scope '/service_assurance' do
    get '/', to: 'service_assurance/cases#index', as: 'service_assurance'
    get '/cases', to: 'service_assurance/cases#index'
    get '/cases/export', to: 'service_assurance/cases#export'
    get '/cases/netbox_search', to: 'service_assurance/cases#netbox_search'
    post '/cases/netbox_sync', to: 'service_assurance/cases#netbox_sync'
    get '/cases/:id', to: 'service_assurance/cases#show', constraints: { id: /\d+/ }, as: 'service_assurance_case'
    post '/cases/open', to: 'service_assurance/cases#open'
    patch '/cases/:id', to: 'service_assurance/cases#update', constraints: { id: /\d+/ }
    post '/cases/:id/evaluate', to: 'service_assurance/cases#evaluate', constraints: { id: /\d+/ }
    post '/cases/:id/conciliate', to: 'service_assurance/cases#conciliate', constraints: { id: /\d+/ }
    post '/cases/:id/reopen', to: 'service_assurance/cases#reopen', constraints: { id: /\d+/ }
    get '/admin', to: 'service_assurance/admin#show'
  end
  namespace :service_assurance do
    namespace :api do
      namespace :v1 do
        get 'cases', to: 'cases#index'
        get 'cases/:id', to: 'cases#show', constraints: { id: /\d+/ }
      end
    end
  end
end
