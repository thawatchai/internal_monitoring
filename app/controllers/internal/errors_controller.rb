# frozen_string_literal: true

require 'zlib'

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
      log_files_for.each do |path|
        next unless File.exist?(path)

        collect_entries_from(path, since, severities, entries)
      end
      finalize_entries(entries)
    end

    def collect_entries_from(path, since, severities, entries)
      current_entry = nil

      each_log_line(path) do |line|
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

    # logrotate compresses everything but the live file.
    def each_log_line(path, &block)
      if path.to_s.end_with?('.gz')
        Zlib::GzipReader.open(path) { |gz| gz.each_line(&block) }
      else
        File.foreach(path, &block)
      end
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

    # Every rotation of the error log, however it was produced.
    #
    # This used to reconstruct rotation dates and look for
    # `production_errors.log-YYYYMMDD`. Nothing writes that name: logrotate is
    # configured with `compress`, so it produces `-YYYYMMDD.gz`, and Rails'
    # Logger shift_age produced `.YYYYMMDD`. The guess matched neither, and
    # parse_log_entries skips a missing path silently, so every query wider than
    # the current file quietly returned only today's errors while reporting the
    # window the caller asked for.
    #
    # Globbing removes the guess. Entries are filtered by timestamp in
    # flush_entry regardless, so matching broadly costs a little reading and
    # cannot miss a file.
    def log_files_for
      log_dir = Rails.root.join('log')
      files = Dir[File.join(log_dir, 'production_errors.log*')].sort

      # Only for an app that has not written an error log yet.
      files.presence || [log_dir.join('production.log').to_s]
    end

    def parse_log_line(line)
      m = line.match(LOG_PATTERN)
      return unless m

      { timestamp: Time.zone.parse(m[1]), pid: m[2], severity: m[3], message: m[4].rstrip }
    end
  end
end
