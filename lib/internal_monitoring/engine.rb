# frozen_string_literal: true

module InternalMonitoring
  class Engine < ::Rails::Engine
  end

  # Call this from your routes file to draw the engine's routes.
  # Must be placed before any catch-all route.
  #
  #   # config/routes/misc.rb
  #   InternalMonitoring.draw_routes(self)
  #   match '*anything' => 'web/home#not_found', ...
  #
  def self.draw_routes(router)
    router.scope defaults: { format: :json } do
      router.namespace :internal do
        router.resources :errors, only: [:index]
      end
    end
  end
end
