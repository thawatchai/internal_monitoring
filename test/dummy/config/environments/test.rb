# frozen_string_literal: true

Rails.application.configure do
  config.eager_load = false
  config.cache_store = :memory_store
  config.action_controller.perform_caching = false
  config.action_controller.allow_forgery_protection = false
  config.action_mailer.delivery_method = :test
  config.action_mailer.perform_caching = false
  config.active_support.deprecation = :stderr
end
