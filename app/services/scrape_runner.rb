# The orchestrator -- this is the Ruby equivalent of Python's
# src/main.py. One call to `ScrapeRunner.call` runs every configured
# search (MacBook Pro, iPhone Pro Max, iPad Pro, the e-bike search)
# against every enabled marketplace, saves what it finds, scores it,
# and sends Discord alerts for anything worth seeing. This is what the
# recurring Solid Queue job (config/recurring.yml) calls on a schedule.
class ScrapeRunner
  # ── The searches this app runs, one per "thing we're shopping for" ──
  # A direct port of config.yaml's `searches:` list, minus the Python
  # version's auto-expanding `generation_family:` macro (see README) --
  # here the last-3-generations window is just spelled out directly, so
  # bumping to the next chip/iPhone generation next year is a one-line
  # edit to chip_options/model_keywords below rather than a YAML macro.
  SEARCHES = [
    {
      product_name: "MacBook Pro",
      product_type: :electronics,
      screen_sizes: [ 14, 16 ],              # 14" preferred, 16" an accepted fallback
      ram_gb_primary: 128,
      ram_gb_fallback: 64,
      storage_gb_min: 1024,                  # 1TB minimum
      storage_gb_max: nil,
      # Newest-first -- ElectronicsHandler's chip-generation bonus in
      # Listing#electronics_spec_bonus rewards an earlier index higher.
      chip_options: [ "M5 Max", "M4 Max", "M3 Max" ],
      cellular: false,
      location: nil,
      results_per_size: 30,
      discord_webhook_env: "DISCORD_WEBHOOK_URL"
    },
    {
      product_name: "iPhone Pro Max",
      product_type: :electronics,
      screen_sizes: [],
      ram_gb_primary: nil,
      ram_gb_fallback: nil,
      storage_gb_min: 1000,                  # 1TB minimum (also covers 2TB)
      storage_gb_max: nil,
      model_keywords: [ "iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 15 Pro Max" ],
      cellular: false,
      location: nil,
      results_per_size: 30,
      discord_webhook_env: "DISCORD_WEBHOOK_URL"
    },
    {
      product_name: "iPad Pro",
      product_type: :electronics,
      screen_sizes: [ 13, 11 ],              # 13" preferred, 11" an accepted fallback
      ram_gb_primary: 16,
      ram_gb_fallback: nil,
      storage_gb_min: 512,
      storage_gb_max: nil,
      chip_options: [ "M5", "M4", "M3" ],    # iPad Pro uses base M chips, not a "Pro"/"Max" tier
      cellular: true,                         # WiFi + Cellular models only
      location: nil,
      results_per_size: 30,
      discord_webhook_env: "DISCORD_WEBHOOK_URL"
    },
    {
      product_name: "Folding step-through commuter e-bike",
      product_type: :ebike,
      screen_sizes: [],
      ram_gb_primary: nil,
      ram_gb_fallback: nil,
      storage_gb_min: nil,
      storage_gb_max: nil,
      cellular: false,
      location: "Phoenix, AZ",
      results_per_size: 40,
      wheel_sizes_in: [ 16, 20, 24 ],
      min_weight_capacity_lb: 330,
      preferred_brands: SpecParser::EBIKE_KNOWN_BRANDS,
      # A dedicated Discord channel, separate from the three Apple
      # hardware searches above, so e-bike alerts don't drown out (or
      # get drowned out by) MacBook/iPhone/iPad alerts.
      discord_webhook_env: "DISCORD_WEBHOOK_URL_EBIKE"
    }
  ].freeze

  # ── Which marketplaces we scrape, and which searches each applies to ──
  # `nil` for applicable_product_types means "every search" (the general
  # marketplaces); a specific list means "only these product types,"
  # matching config.yaml's `applicable_product_types:` restriction --
  # e.g. Apple Refurb/BestBuy/Newegg/Gazelle/Swappa never carry e-bikes,
  # and Pinkbike never carries anything BUT e-bikes.
  SITES = [
    { source: "ebay", scraper: -> { Scrapers::EbayScraper }, applicable_product_types: nil },
    { source: "swappa", scraper: -> { Scrapers::SwappaScraper }, applicable_product_types: [ :electronics ] },
    { source: "apple_refurb", scraper: -> { Scrapers::AppleRefurbScraper }, applicable_product_types: [ :electronics ] },
    { source: "backmarket", scraper: -> { Scrapers::BackmarketScraper }, applicable_product_types: [ :electronics ] },
    { source: "mercari", scraper: -> { Scrapers::MercariScraper }, applicable_product_types: nil },
    { source: "bestbuy", scraper: -> { Scrapers::BestbuyScraper }, applicable_product_types: [ :electronics ] },
    { source: "offerup", scraper: -> { Scrapers::OfferupScraper }, applicable_product_types: nil },
    { source: "newegg", scraper: -> { Scrapers::NeweggScraper }, applicable_product_types: [ :electronics ] },
    { source: "gazelle", scraper: -> { Scrapers::GazelleScraper }, applicable_product_types: [ :electronics ] },
    { source: "craigslist", scraper: -> { Scrapers::CraigslistScraper }, applicable_product_types: nil },
    { source: "pinkbike", scraper: -> { Scrapers::PinkbikeScraper }, applicable_product_types: [ :ebike ] }
  ].freeze

  # A listing not seen again in a scrape for 72+ hours is probably sold
  # or taken down -- matches Python's expire_stale_listings default.
  STALE_AFTER_HOURS = 72

  # A great deal that vanishes within this many hours of first being
  # seen was very likely bought by someone else -- matches Python's
  # SCOOPED_DEAL_HOURS.
  SCOOPED_DEAL_HOURS = 24

  # Delete listings.rb rows that have been inactive for this long --
  # keeps the SQLite file from growing forever. Matches Python's
  # RETENTION_DAYS.
  RETENTION_DAYS = 180

  # `search_for` is how Listing#electronics_spec_bonus/ebike_spec_bonus
  # look up the full search config (ram tiers, chip window, etc.) for
  # whatever search a listing came from, keyed by the listing's own
  # search_name column.
  def self.search_for(product_name)
    SEARCHES.find { |search| search[:product_name] == product_name }
  end

  # The one entry point the recurring job calls -- runs every search in
  # turn, expiring/pruning old listings once up front (not once per
  # search, since "have we seen this listing in the last 72h" is a
  # whole-database question, not a per-search one).
  def self.call
    new.call
  end

  def call
    expire_stale_and_alert_scooped!
    prune_old_inactive_listings!

    SEARCHES.each { |search| run_one_search(search) }
  end

  private

  def run_one_search(search)
    Rails.logger.info("[ScrapeRunner] Searching for: #{search[:product_name]}")

    scraped = run_scrapers(search)
    Rails.logger.info("[ScrapeRunner] #{search[:product_name]}: #{scraped.length} raw listings found")

    saved_listings = []
    price_drops = []

    scraped.each do |candidate|
      listing, old_price = upsert_listing(candidate, search)
      next unless listing

      saved_listings << listing
      if old_price && PriceAnalyzer.meaningful_drop?(old_price, listing.price_usd)
        price_drops << [ listing, old_price ]
      end
    end

    top_deals = PriceAnalyzer.call(saved_listings)
    stats = PriceAnalyzer.new(saved_listings).stats
    top_deals = top_deals.first(15)

    has_great_deal = top_deals.any?(&:is_great_deal?)
    DiscordNotifier.send_alert(search, top_deals, stats) if has_great_deal
    DiscordNotifier.send_price_drop_alert(search, price_drops) if price_drops.any?
  rescue => e
    # One search failing (a marketplace's page layout changed, a
    # timeout, whatever) shouldn't stop the other three searches from
    # running -- matches Python's per-scraper try/except in main.py.
    Rails.logger.error("[ScrapeRunner] #{search[:product_name]} failed: #{e.class}: #{e.message}")
  end

  # Runs every enabled, applicable scraper for this search and
  # flattens their results into one array -- one marketplace failing
  # (network error, layout change) doesn't stop the others.
  def run_scrapers(search)
    SITES.filter_map do |site|
      next if site[:applicable_product_types] && !site[:applicable_product_types].include?(search[:product_type])

      begin
        site[:scraper].call.new(search).scrape
      rescue => e
        Rails.logger.warn("[ScrapeRunner] #{site[:source]} failed: #{e.class}: #{e.message}")
        []
      end
    end.flatten
  end

  # Finds-or-creates the Listing row for one scraped candidate, mirrors
  # Python's listing_to_db -- returns [listing, price_before_this_update]
  # so the caller can detect a meaningful price drop on an
  # already-known listing. Also records a PriceHistory row whenever the
  # price is new or has changed.
  def upsert_listing(candidate, search)
    listing = Listing.find_or_initialize_by(source: candidate[:source], listing_id: candidate[:listing_id])
    old_price = listing.persisted? ? listing.price_usd : nil

    listing.assign_attributes(
      candidate.except(:source, :listing_id).merge(
        product_type: search[:product_type].to_s,
        search_name: search[:product_name],
        last_seen_at: Time.current,
        is_active: true
      )
    )
    listing.first_seen_at ||= Time.current

    unless listing.save
      Rails.logger.warn("[ScrapeRunner] could not save listing #{candidate[:source]}##{candidate[:listing_id]}: #{listing.errors.full_messages.join(', ')}")
      return [ nil, nil ]
    end

    PriceHistory.record_if_changed!(listing, listing.price_usd)

    [ listing, old_price ]
  end

  # A listing we haven't seen in 72+ hours is probably gone -- flip it
  # inactive (never delete outright, see prune_old_inactive_listings!
  # below for the separate long-term cleanup) and alert on any that
  # were a great deal and vanished within SCOOPED_DEAL_HOURS, a strong
  # signal someone else bought it.
  def expire_stale_and_alert_scooped!
    cutoff = STALE_AFTER_HOURS.hours.ago
    stale = Listing.active.where("last_seen_at < ?", cutoff)

    scooped_by_search = Hash.new { |hash, key| hash[key] = [] }
    stale.find_each do |listing|
      if listing.is_great_deal? && listing.first_seen_at && listing.last_seen_at &&
          (listing.last_seen_at - listing.first_seen_at) <= SCOOPED_DEAL_HOURS.hours
        scooped_by_search[listing.search_name] << listing
      end
      listing.update!(is_active: false)
    end

    scooped_by_search.each do |search_name, listings|
      search = self.class.search_for(search_name)
      DiscordNotifier.send_scooped_deal_alert(search, listings) if search
    end
  end

  # Hard-deletes listings that have been inactive for RETENTION_DAYS+
  # -- keeps the database from growing forever. Safe: it only ever
  # touches rows already flipped inactive above, active listings are
  # never removed regardless of age.
  def prune_old_inactive_listings!
    cutoff = RETENTION_DAYS.days.ago
    Listing.where(is_active: false).where("last_seen_at < ?", cutoff).find_each(&:destroy)
  end
end
