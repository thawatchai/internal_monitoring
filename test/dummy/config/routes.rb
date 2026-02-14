# frozen_string_literal: true

Dummy::Application.routes.draw do
  InternalMonitoring.draw_routes(self)
end
