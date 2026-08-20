module Scrapers
  # The shared foundation every marketplace scraper builds on -- a
  # direct port of Python's `BaseScraper` (src/scrapers/base.py). It
  # owns two things every scraper needs: a polite, retrying HTTP
  # fetcher for plain HTML/JSON pages, and a headless-Chrome fetcher
  # (via the `ferrum` gem) for the handful of sites whose listings only
  # exist after JavaScript runs.
  class BaseScraper
    # A realistic pool of desktop browser user-agent strings, rotated
    # per request -- some marketplaces are quicker to flag a scraper
    # that always sends the exact same UA on every single request.
    USER_AGENTS = [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    ].freeze

    def initialize(search)
      @search = search
    end

    # Every subclass must implement this, returning an Array of Hashes
    # shaped like Listing's own attributes (source/listing_id/title/
    # price_usd/url/condition/location plus whatever spec fields
    # apply), already passed through `build_candidate` below so only
    # listings that survive our own filters come back.
    def scrape
      raise NotImplementedError, "#{self.class} must implement #scrape"
    end

    private

    attr_reader :search

    # Fetches a plain HTML/JSON page with a polite delay and a few
    # retries on the errors that usually mean "try again, not never" --
    # a rate limit (429), a transient 5xx, or a network hiccup. Matches
    # Python's fetch_page.
    def fetch(url, max_retries: 3)
      last_error = nil

      max_retries.times do |attempt|
        # Skip the polite delay in the test environment -- there's no
        # real marketplace on the other end of a WebMock stub to be
        # polite to, and this is the single biggest thing that would
        # otherwise make the test suite slow to run.
        sleep(1.0 + rand) unless Rails.env.test?
        response = connection.get(url)

        return response.body if response.status < 400

        if [ 403, 429, 500, 502, 503 ].include?(response.status)
          Rails.logger.info("[#{self.class}] HTTP #{response.status} on attempt #{attempt + 1}, retrying...")
          last_error = "HTTP #{response.status}"
          sleep(2)
          next
        end

        response.raise_for_status! rescue nil
        raise "HTTP #{response.status} fetching #{url}"
      end

      raise "Failed after #{max_retries} attempts: #{url} (#{last_error})"
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.response :follow_redirects
        f.options.timeout = 30
        f.headers["User-Agent"] = USER_AGENTS.sample
        f.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        f.headers["Accept-Language"] = "en-US,en;q=0.9"
      end
    end

    # For the sites whose listings genuinely don't exist in the raw
    # HTML at all -- they're painted in by JavaScript after the page
    # loads. Drives a real (headless) Chrome via `ferrum`, matches
    # Python's fetch_with_playwright. `wait` gives the page's JS a
    # moment to finish rendering before we grab its HTML.
    def fetch_rendered(url, wait: 3)
      # BROWSER_PATH lets the Docker image (which installs Chromium
      # under a name Ferrum doesn't look for automatically -- see
      # Dockerfile) point Ferrum at the right binary; left unset,
      # Ferrum falls back to hunting for a Chrome/Chromium install on
      # its own, which is normally enough for local development.
      options = { headless: true, timeout: 30, browser_options: { "no-sandbox" => nil } }
      options[:browser_path] = ENV["BROWSER_PATH"] if ENV["BROWSER_PATH"].present?

      browser = Ferrum::Browser.new(**options)
      browser.goto(url)
      sleep(wait)
      browser.body
    ensure
      browser&.quit
    end

    def parse_html(html)
      Nokogiri::HTML(html)
    end

    # Pulls the numeric price out of a text string like "$1,299.00" or
    # "US $899.99" -- every scraper needs this, so it lives here once.
    def parse_price(text)
      return nil if text.blank?

      match = text.to_s.gsub(",", "").match(/(\d+(?:\.\d{1,2})?)/)
      match && match[1].to_f
    end

    # Builds one candidate listing Hash from raw scraped fields, runs
    # it through SpecParser (electronics or e-bike, whichever this
    # search needs) and ListingFilter, and returns nil if it doesn't
    # belong in our results -- an accessory, the wrong spec, priced
    # outside our range. Every scraper's #scrape method should route
    # every raw item it finds through this one method, so every scraper
    # applies identical rules.
    def build_candidate(source:, listing_id:, title:, price_usd:, url:, condition: nil, location: nil)
      return nil if title.blank? || price_usd.blank? || listing_id.blank?

      parsed = search[:product_type] == :ebike ? SpecParser.parse_ebike(title) : SpecParser.parse_electronics(title)

      return nil unless ListingFilter.passes?(
        title: title, condition: condition, price_usd: price_usd, location: location,
        parsed: parsed, search: search
      )

      {
        source: source,
        listing_id: listing_id.to_s,
        title: title.to_s.strip,
        price_usd: price_usd.to_f,
        url: url,
        condition: condition,
        location: location
      }.merge(parsed)
    end
  end
end
