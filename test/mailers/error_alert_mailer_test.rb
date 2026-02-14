# frozen_string_literal: true

require 'test_helper'

module InternalMonitoring
  class ErrorAlertMailerTest < ActionMailer::TestCase
    setup do
      ENV['TEST_ERROR_ALERT_EMAIL'] = 'admin@example.com'
    end

    teardown do
      ENV.delete('TEST_ERROR_ALERT_EMAIL')
    end

    test 'error_occurred sends email with exception details' do
      error_data = build_error_data('Something broke')
      context = {
        url: 'https://example.org/courses/1',
        controller: 'Api::CoursesController',
        action: 'show',
        params: { id: '1' },
        user_id: 42
      }

      mail = InternalMonitoring::ErrorAlertMailer.error_occurred(error_data, context)

      assert_equal ['admin@example.com'], mail.to
      assert_includes mail.subject, 'ERROR:'
      assert_includes mail.subject, 'RuntimeError'
      assert_includes mail.subject, 'Api::CoursesController#show'
      assert_includes mail.subject, '[TestApp]'

      body = mail.body.decoded
      assert_includes body, 'Something broke'
      assert_includes body, 'https://example.org/courses/1'
      assert_includes body, 'Api::CoursesController'
      assert_includes body, 'User ID: 42'
    end

    test 'error_occurred includes backtrace in body' do
      error_data = build_error_data('Crash')
      mail = InternalMonitoring::ErrorAlertMailer.error_occurred(error_data, {})
      body = mail.body.decoded

      assert_includes body, 'Backtrace'
      assert_includes body, 'test_file.rb:10'
    end

    test 'error_occurred sends to empty when no recipient configured' do
      ENV.delete('TEST_ERROR_ALERT_EMAIL')

      error_data = build_error_data('No recipient')
      mail = InternalMonitoring::ErrorAlertMailer.error_occurred(error_data, {})

      assert_empty mail.to
    end

    test 'error_occurred uses Background label when no controller context' do
      error_data = build_error_data('Background job failed')
      mail = InternalMonitoring::ErrorAlertMailer.error_occurred(error_data, {})

      assert_includes mail.subject, 'in Background'
    end

    test 'error_occurred uses configured app_name in subject' do
      error_data = build_error_data('Test')
      mail = InternalMonitoring::ErrorAlertMailer.error_occurred(error_data, { controller: 'Foo', action: 'bar' })

      assert_includes mail.subject, '[TestApp]'
    end

    private

    def build_error_data(message)
      {
        class_name: 'RuntimeError',
        message: message,
        backtrace: [
          'test_file.rb:10:in `method_a\'',
          'test_file.rb:20:in `method_b\'',
          'test_file.rb:30:in `method_c\''
        ]
      }
    end
  end
end
