# frozen_string_literal: true

module Internal
  class ErrorsController < ActionController::Base
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :verify_authenticity_token, raise: false
    skip_before_action :set_current_context, raise: false
    skip_before_action :save_last_get_request_url, raise: false
    before_action :authenticate_internal_api!

    MAX_HOURS = 168 # 7 days

    # Ruby Logger format: "E, [2026-02-13T12:35:46.693252 #PID]  ERROR -- : [request_id] message"
    LOG_PATTERN = /\A[A-Z],\s+\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)\s+\#(\d+)\]\s+
                    ([A-Z]+)\s+--\s+:\s*(.*)
                 /x

    def index
      hours = params.fetch(:hours, 24).to_i.clamp(1, MAX_HOURS)
      severities = (params[:severity].presence || 'ERROR,FATAL').upcase.split(',')
      since = hours.hours.ago

      entries = parse_log_entries(since, severities)

      render json: {
        count: entries.size,
        hours: hours,
        severities: severities,
        entries: entries
      }
    end

    private

    def authenticate_internal_api!
      expected = InternalMonitoring.api_key
      if expected.blank?
        render json: { error: 'Internal API not configured' }, status: :service_unavailable
        return
      end

      provided = bearer_token
      return if ActiveSupport::SecurityUtils.secure_compare(provided.to_s, expected)

      render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    def bearer_token
      header = request.headers['Authorization'].to_s
      header.match(/\ABearer (.+)\z/)&.captures&.first
    end

    def parse_log_entries(since, severities)
      entries = []
      log_files_for(since).each do |path|
        next unless File.exist?(path)

        collect_entries_from(path, since, severities, entries)
      end
      finalize_entries(entries)
    end

    def collect_entries_from(path, since, severities, entries)
      current_entry = nil

      File.foreach(path) do |line|
        match = parse_log_line(line)
        if match
          flush_entry(current_entry, since, severities, entries)
          current_entry = build_entry(match)
        elsif current_entry
          current_entry[:backtrace] << line.rstrip
        end
      end

      flush_entry(current_entry, since, severities, entries)
    end

    def build_entry(match)
      {
        timestamp: match[:timestamp],
        severity: match[:severity],
        pid: match[:pid],
        message: match[:message],
        backtrace: []
      }
    end

    def flush_entry(entry, since, severities, entries)
      return unless entry
      return unless entry[:timestamp] >= since && severities.include?(entry[:severity])

      entries << entry
    end

    def finalize_entries(entries)
      entries.each do |entry|
        entry[:backtrace].reject!(&:blank?)
        entry[:timestamp] = entry[:timestamp].iso8601(3)
      end
      entries.sort_by { |e| e[:timestamp] }.reverse
    end

    # Returns log file paths to read.
    # Handles daily rotation: today's file + yesterday's if time range spans midnight.
    def log_files_for(since)
      log_dir = Rails.root.join('log')
      today = Time.current.to_date
      files = [log_dir.join('production_errors.log')]

      # Rotated files are named by rotation date (day after the logs).
      # production_errors.log-20260214 contains Feb 13's errors (rotated at midnight Feb 14).
      # So for errors from date X, we need production_errors.log-{X+1}.
      (since.to_date..today).each do |date|
        rotation_date = date + 1.day
        rotated = log_dir.join("production_errors.log-#{rotation_date.strftime('%Y%m%d')}")
        files << rotated
      end

      # Fall back to production.log if no error-only log files exist yet
      files = [log_dir.join('production.log')] if files.none? { |f| File.exist?(f) }

      files
    end

    def parse_log_line(line)
      m = line.match(LOG_PATTERN)
      return unless m

      { timestamp: Time.zone.parse(m[1]), pid: m[2], severity: m[3], message: m[4].rstrip }
    end
  end
end
