# frozen_string_literal: true

module InternalMonitoring
  class Engine < ::Rails::Engine
    # Draw the engine's routes directly into the host app
    initializer 'internal_monitoring.append_routes' do |app|
      app.routes.append do
        scope defaults: { format: :json } do
          namespace :internal do
            resources :errors, only: [:index]
          end
        end
      end
    end
  end
end
