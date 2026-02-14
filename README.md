# internal_monitoring

Shared Rails engine for error monitoring across apps (ClassStart, GotoKnow).

## Setup on New Dev Machines

Run this once per app to enable local engine development:

```bash
bundle config set local.internal_monitoring /path/to/internal_monitoring
```

This makes Bundler use your local checkout instead of fetching from GitHub.
The local repo must be on the `master` branch for the override to work.

To remove the override:

```bash
bundle config unset local.internal_monitoring
```
