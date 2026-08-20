source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"

# ── Scraper-specific gems ──────────────────────────────────────────
# Nokogiri parses the raw HTML we pull down into something we can
# search with CSS selectors, it's the Ruby equivalent of Python's
# BeautifulSoup, which the original scraper used for the same job.
gem "nokogiri"
# Faraday is our HTTP client for the plain, non-JS marketplace pages
# (eBay's initial HTML, Swappa's JSON API, Newegg, Gazelle, Craigslist,
# Apple Refurb) — the Ruby equivalent of Python's `requests` library.
gem "faraday"
gem "faraday-follow_redirects"
# Ferrum drives a real headless Chrome browser for the handful of
# sites whose listings only show up after JavaScript runs (eBay's
# infinite-scroll grid, BackMarket, Best Buy, Mercari, OfferUp,
# Pinkbike) — this plays the same role Playwright played in the
# Python version, just from the Ruby side.
gem "ferrum"
# Loads DISCORD_WEBHOOK_URL and friends from a local .env file so a
# developer never has to export environment variables by hand before
# running the scraper on their own machine.
gem "dotenv-rails"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  # WebMock intercepts every outbound HTTP call in the test suite so
  # scraper tests run against canned responses instead of the real
  # internet, no live network calls, no flaky tests when a real
  # marketplace changes its page.
  gem "webmock"
end
