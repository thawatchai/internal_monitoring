# frozen_string_literal: true

module InternalMonitoring
  class ErrorAlertMailer < ActionMailer::Base
    def error_occurred(error_data, request_context = {})
      @error = error_data
      @context = request_context
      @timestamp = Time.current
      @app_name = InternalMonitoring.configuration.app_name

      recipient = InternalMonitoring.error_alert_email
      controller_action = [@context[:controller], @context[:action]].compact.join('#')
      label = controller_action.presence || 'Background'

      mail(
        to: recipient.presence || [],
        subject: "[#{@app_name}] ERROR: #{@error[:class_name]} in #{label}"
      )
    end
  end
end
