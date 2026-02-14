# frozen_string_literal: true

require 'test_helper'

module Internal
  class ErrorsControllerTest < ActionDispatch::IntegrationTest
    API_KEY = 'test-internal-api-key'

    setup do
      ENV['TEST_INTERNAL_API_KEY'] = API_KEY
    end

    teardown do
      ENV.delete('TEST_INTERNAL_API_KEY')
    end

    # -- Authentication ---------------------------------------------------

    test 'returns 401 without authorization header' do
      get '/internal/errors.json'
      assert_response :unauthorized
      assert_equal 'Unauthorized', response.parsed_body['error']
    end

    test 'returns 401 with wrong api key' do
      get '/internal/errors.json',
          headers: { 'Authorization' => 'Bearer wrong-key' }
      assert_response :unauthorized
    end

    test 'authenticates via Bearer token header' do
      with_log_file('') do
        get '/internal/errors.json',
            headers: auth_headers
        assert_response :success
      end
    end

    test 'returns 503 when api key not configured' do
      ENV.delete('TEST_INTERNAL_API_KEY')
      get '/internal/errors.json',
          headers: { 'Authorization' => 'Bearer anything' }
      assert_response :service_unavailable
    end

    # -- Log parsing ------------------------------------------------------

    test 'returns empty entries when log file is empty' do
      with_log_file('') do
        get '/internal/errors.json', headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal 0, body['count']
        assert_equal [], body['entries']
      end
    end

    test 'parses ERROR entries from log' do
      ts = 1.hour.ago
      log_content = <<~LOG
        #{log_line(ts, 1234, 'INFO', 'Normal request')}
        #{log_line(ts, 1234, 'ERROR', 'Something went wrong')}
        #{log_line(ts, 1234, 'INFO', 'Another normal request')}
      LOG

      with_log_file(log_content) do
        get '/internal/errors.json',
            headers: auth_headers,
            params: { hours: 24 }
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body['count']
        assert_equal 'ERROR', body['entries'].first['severity']
        assert_includes body['entries'].first['message'], 'Something went wrong'
      end
    end

    test 'parses FATAL entries' do
      ts = 30.minutes.ago
      log_content = "#{log_line(ts, 99, 'FATAL', 'Server crashed')}\n"

      with_log_file(log_content) do
        get '/internal/errors.json',
            headers: auth_headers,
            params: { severity: 'FATAL' }
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body['count']
        assert_equal 'FATAL', body['entries'].first['severity']
      end
    end

    test 'captures backtrace lines' do
      ts = 30.minutes.ago
      log_content = <<~LOG
        #{log_line(ts, 1, 'ERROR', 'NoMethodError undefined method')}
          app/models/user.rb:42:in `something'
          app/controllers/api/users_controller.rb:10:in `show'
      LOG

      with_log_file(log_content) do
        get '/internal/errors.json', headers: auth_headers
        assert_response :success
        body = response.parsed_body
        entry = body['entries'].first
        assert_equal 2, entry['backtrace'].size
        assert_includes entry['backtrace'].first, 'user.rb:42'
      end
    end

    test 'filters by time range (hours param)' do
      log_content = <<~LOG
        #{log_line(48.hours.ago, 1, 'ERROR', 'Old error')}
        #{log_line(1.hour.ago, 1, 'ERROR', 'Recent error')}
      LOG

      with_log_file(log_content) do
        get '/internal/errors.json',
            headers: auth_headers,
            params: { hours: 2 }
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body['count']
        assert_includes body['entries'].first['message'], 'Recent error'
      end
    end

    test 'clamps hours to max 168' do
      with_log_file('') do
        get '/internal/errors.json',
            headers: auth_headers,
            params: { hours: 999 }
        assert_response :success
        assert_equal 168, response.parsed_body['hours']
      end
    end

    test 'returns entries sorted newest first' do
      log_content = <<~LOG
        #{log_line(2.hours.ago, 1, 'ERROR', 'First error')}
        #{log_line(1.hour.ago, 1, 'ERROR', 'Second error')}
      LOG

      with_log_file(log_content) do
        get '/internal/errors.json', headers: auth_headers
        assert_response :success
        entries = response.parsed_body['entries']
        assert_equal 2, entries.size
        assert_includes entries.first['message'], 'Second error'
        assert_includes entries.last['message'], 'First error'
      end
    end

    test 'reads rotated log files with hyphen naming' do
      tomorrow = (Time.current.to_date + 1.day).strftime('%Y%m%d')
      rotated_name = "production.log-#{tomorrow}"
      log_content = "#{log_line(1.hour.ago, 1, 'ERROR', 'Rotated file error')}\n"

      with_rotated_log_file(rotated_name, log_content) do
        with_log_file('') do
          get '/internal/errors.json', headers: auth_headers
          assert_response :success
          body = response.parsed_body
          assert_equal 1, body['count']
          assert_includes body['entries'].first['message'], 'Rotated file error'
        end
      end
    end

    test 'JSON response structure' do
      log_content = "#{log_line(1.hour.ago, 42, 'ERROR', 'Test error')}\n"

      with_log_file(log_content) do
        get '/internal/errors.json', headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert body.key?('count')
        assert body.key?('hours')
        assert body.key?('severities')
        assert body.key?('entries')

        entry = body['entries'].first
        assert entry.key?('timestamp')
        assert entry.key?('severity')
        assert entry.key?('pid')
        assert entry.key?('message')
        assert entry.key?('backtrace')
      end
    end

    private

    def auth_headers
      { 'Authorization' => "Bearer #{API_KEY}" }
    end

    def log_line(time, pid, severity, message)
      letter = severity[0]
      ts = time.strftime('%Y-%m-%dT%H:%M:%S.%6N')
      "#{letter}, [#{ts} ##{pid}] #{severity.rjust(5)} -- : #{message}"
    end

    def with_log_file(content)
      log_path = Rails.root.join('log/production.log')
      FileUtils.mkdir_p(File.dirname(log_path))
      original = File.exist?(log_path) ? File.read(log_path) : nil

      File.write(log_path, content)
      yield
    ensure
      if original
        File.write(log_path, original)
      else
        FileUtils.rm_f(log_path)
      end
    end

    def with_rotated_log_file(filename, content)
      log_path = Rails.root.join("log/#{filename}")
      FileUtils.mkdir_p(File.dirname(log_path))
      original = File.exist?(log_path) ? File.read(log_path) : nil

      File.write(log_path, content)
      yield
    ensure
      if original
        File.write(log_path, original)
      else
        FileUtils.rm_f(log_path)
      end
    end
  end
end
