# frozen_string_literal: true

require 'internal_monitoring/engine'

module InternalMonitoring
  class Configuration
    attr_accessor :app_name, :env_prefix

    def initialize
      @app_name = 'App'
      @env_prefix = 'APP'
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Read API key from credentials or ENV
    def api_key
      Rails.application.credentials.dig(:internal_api, :api_key) ||
        ENV.fetch("#{configuration.env_prefix}_INTERNAL_API_KEY", nil)
    end

    # Read alert email from credentials or ENV
    def error_alert_email
      Rails.application.credentials.dig(:internal_api, :error_alert_email) ||
        ENV.fetch("#{configuration.env_prefix}_ERROR_ALERT_EMAIL", nil)
    end

    # Public API: send an error alert email with deduplication.
    # +exception+ - the exception object
    # +context+   - hash with :url, :controller, :action, :params, :user_id
    def send_error_alert(exception, context = {})
      fingerprint = "#{exception.class}:#{exception.message}"
      cache_key = "error_alert:#{Digest::MD5.hexdigest(fingerprint)}"
      return if Rails.cache.exist?(cache_key)

      Rails.cache.write(cache_key, true, expires_in: 1.hour)

      error_data = {
        class_name: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace&.first(15) || []
      }
      InternalMonitoring::ErrorAlertMailer.error_occurred(error_data, context).deliver_later
    rescue StandardError => e
      Rails.logger.error("InternalMonitoring::ErrorAlertMailer failed: #{e.message}")
    end
  end
end
