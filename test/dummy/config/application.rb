# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'active_support/railtie'
require 'internal_monitoring'

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.cache_store = :memory_store
    config.active_support.deprecation = :stderr
    config.secret_key_base = 'test-secret-key-base-for-internal-monitoring-engine'
  end
end
