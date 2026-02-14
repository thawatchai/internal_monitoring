# CLAUDE.md

## What This Is

Shared Rails engine providing error monitoring for multiple apps (ClassStart, GotoKnow).
Extracted from ClassStart to avoid code duplication.

## Structure

```
app/controllers/internal/errors_controller.rb   # Log parsing API (/internal/errors.json)
app/mailers/internal_monitoring/error_alert_mailer.rb  # Error email alerts
app/views/internal_monitoring/error_alert_mailer/      # Mailer templates
lib/internal_monitoring.rb                       # Configuration + public API
lib/internal_monitoring/engine.rb                # Rails engine setup
test/                                            # Engine tests with dummy app
```

## How It Works

### Configuration (in host app initializer)
```ruby
InternalMonitoring.configure do |config|
  config.app_name = 'ClassStart'   # Used in email subject: [ClassStart] ERROR: ...
  config.env_prefix = 'CS'         # ENV fallback prefix: CS_INTERNAL_API_KEY
end
```

### Credentials
Reads from Rails credentials first, falls back to ENV:
- `credentials.internal_api.api_key` or `ENV["{prefix}_INTERNAL_API_KEY"]`
- `credentials.internal_api.error_alert_email` or `ENV["{prefix}_ERROR_ALERT_EMAIL"]`

### Public API
```ruby
InternalMonitoring.send_error_alert(exception, context)
```
Sends email alert with 1-hour deduplication via `Rails.cache`.

### Routes
Auto-mounted into host app: `GET /internal/errors.json` (Bearer token auth).

## Running Tests

```bash
bundle install
bundle exec rake test
```

## Development Workflow

This engine is used by host apps via git source in their Gemfile:
```ruby
gem 'internal_monitoring', git: 'https://github.com/thawatchai/internal_monitoring.git', branch: 'master'
```

For local development, configure Bundler to use your local checkout instead of fetching from GitHub:
```bash
cd /path/to/host-app/services/rails
bundle config set local.internal_monitoring /path/to/internal_monitoring
```

This makes `bundle install` use the local repo while keeping the git source in the Gemfile for production deploys. Changes to the local repo are picked up immediately without pushing.

**Important**: The local repo must be on the `master` branch for the override to work.

To remove the local override:
```bash
bundle config unset local.internal_monitoring
```

## Host Apps

- **ClassStart** (`usableclass`): `config.app_name = 'ClassStart'`, `config.env_prefix = 'CS'`
- **GotoKnow** (`kv`): `config.app_name = 'GotoKnow'`, `config.env_prefix = 'KV'`
