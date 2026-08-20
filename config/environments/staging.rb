# A REAL Rails environment, distinct from both a local `development`
# run and the real `production` deployment -- this is this app's
# equivalent of the Python project's separate staging GitHub Actions
# workflow (scrape-staging.yml). It runs the exact same code, with
# production-like settings (no code reloading, eager loading, real
# background job backend), but:
#   - posts to a separate, non-production Discord webhook (the "_DEV"
#     env vars DiscordNotifier falls back to for any non-production
#     environment, see that file's webhook_url method)
#   - reads/writes its own storage/staging.sqlite3 database, config/
#     database.yml already gives every Rails environment its own
#     database file automatically, so there's no risk of a staging run
#     ever touching the real production data
#
# WHY THIS EXISTS: a local `development` run only proves the code
# works on YOUR machine. It doesn't prove it works in the real
# deployed runtime (a from-scratch Docker container, no local browser
# cache for Ferrum to lean on) -- that's exactly the gap this
# environment closes: same deployable image, same Solid Queue
# scheduler, just pointed at throwaway data and a throwaway Discord
# channel instead of the real ones. See the README's "Environments"
# section for the full local -> staging -> production flow.
#
# Deliberately just a copy of production.rb's settings -- the whole
# point of staging is behaving exactly like production, not testing a
# DIFFERENT configuration.
require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }
  config.active_storage.service = :local
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false
  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
  config.action_mailer.default_url_options = { host: "example.com" }
  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]
end
