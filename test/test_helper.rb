# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require_relative 'dummy/config/environment'
require 'rails/test_help'

# Configure engine for tests
InternalMonitoring.configure do |config|
  config.app_name = 'TestApp'
  config.env_prefix = 'TEST'
end

# Draw engine routes into the dummy app
Rails.application.routes.draw do
  InternalMonitoring.draw_routes(self)
end
