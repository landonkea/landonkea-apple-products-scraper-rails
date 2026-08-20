# Turns a batch of already-saved Listing rows (all from the same
# search, e.g. every "MacBook Pro" listing found this run) into 0-100
# deal scores, by comparing each listing's price against the group's
# own median rather than a single fixed price. A direct port of
# Python's `PriceAnalyzer` class in price_analyzer.py.
class PriceAnalyzer
  # A listing priced way below the rest of the batch (under half the
  # median) AND described with "new"/"sealed" wording is far more
  # likely mislabeled or a scam than a genuine steal -- a real "New
  # Sealed" iPhone was once found listed at $238 against a true price
  # north of $1,400. Matches Python's SUSPICIOUS_PRICE_RATIO /
  # SUSPICIOUS_MIN_SAMPLE exactly.
  SUSPICIOUS_PRICE_RATIO = 0.5
  SUSPICIOUS_MIN_SAMPLE = 3
  SUSPICIOUS_CONDITION_KEYWORDS = [ "new", "sealed", "brand new", "factory sealed" ].freeze
  SUSPICIOUS_TAG = "⚠️ VERIFY PRICE, "

  # How much each marketplace's listings are trusted, folded straight
  # into the score. Apple's own refurb store and Back Market (graded,
  # warrantied stock) earn the biggest trust bonus; Craigslist and
  # OfferUp (no buyer protection, cash-in-person norm) take the biggest
  # penalty. A direct port of Python's DEFAULT_SOURCE_RELIABILITY_BONUS.
  # This is a nudge, not a gate -- a great price on Craigslist can still
  # easily outscore a mediocre price on Apple Refurb.
  SOURCE_RELIABILITY_BONUS = {
    "apple_refurb" => 2,
    "backmarket" => 2,
    "swappa" => 1,
    "gazelle" => 1,
    "bestbuy" => 1,
    "newegg" => 1,
    "ebay" => 0,
    "mercari" => -1,
    "offerup" => -3,
    "craigslist" => -3
  }.freeze

  # A price drop only counts as "meaningful" (worth its own Discord
  # alert) once it clears BOTH a minimum percent AND a minimum dollar
  # amount -- a percent-only rule fires on trivial drops for cheap
  # items, a dollar-only rule fires on trivial drops for expensive
  # ones. Matches config.yaml's price_drop settings.
  MIN_DROP_PERCENT = 5
  MIN_DROP_USD = 50

  # `call` is the one entry point -- scores every listing in `listings`
  # (all from the same search), saves the scores back to the database,
  # and returns the same array sorted best-score-first.
  def self.call(listings)
    new(listings).call
  end

  def initialize(listings)
    @listings = listings
  end

  def call
    stats = compute_stats

    @listings.each do |listing|
      score = score_listing(listing, stats)
      great_deal = listing.price_usd <= listing.great_deal_price_usd

      if suspicious?(listing, stats)
        # A suspiciously-cheap listing never counts as a vetted "great
        # deal" even if its raw price clears the threshold, and its
        # title gets a visible warning tag so a human glances twice
        # before buying -- matches Python's suspicious-price safeguard.
        great_deal = false
        listing.title = "#{SUSPICIOUS_TAG}#{listing.title}" unless listing.title.start_with?(SUSPICIOUS_TAG)
      end

      listing.update!(deal_score: score, is_great_deal: great_deal, title: listing.title)
    end

    @listings.sort_by { |listing| -(listing.deal_score || 0) }
  end

  # Exposed so ScrapeRunner/DiscordNotifier can show the batch's price
  # range and median alongside individual listing scores, matching the
  # "Market Snapshot" field Python's Discord embed included.
  def stats
    @stats ||= compute_stats
  end

  # `meaningful_drop?` decides whether an already-known listing's price
  # change from `old_price` to `new_price` is worth its own price-drop
  # alert -- a direct port of Python's is_meaningful_price_drop.
  def self.meaningful_drop?(old_price, new_price)
    return false if old_price.nil? || old_price <= 0 || new_price >= old_price

    drop_usd = old_price - new_price
    drop_percent = (drop_usd / old_price) * 100

    drop_usd >= MIN_DROP_USD && drop_percent >= MIN_DROP_PERCENT
  end

  private

  def compute_stats
    return { count: 0, mean: 0.0, median: 0.0, min: 0.0, max: 0.0 } if @listings.empty?

    prices = @listings.map(&:price_usd).sort
    n = prices.length

    {
      count: n,
      mean: (prices.sum / n).round(2),
      median: median(prices),
      min: prices.first,
      max: prices.last
    }
  end

  def median(sorted_prices)
    n = sorted_prices.length
    mid = n / 2
    n.odd? ? sorted_prices[mid] : ((sorted_prices[mid - 1] + sorted_prices[mid]) / 2.0)
  end

  # When there's only one listing (or none) in the batch, there's no
  # meaningful median to compare against -- fall back to a flat score
  # keyed off the fixed great/good-deal thresholds, matching Python's
  # same edge-case fallback.
  def score_listing(listing, stats)
    return baseline_score(listing) if stats[:count].zero?

    score = 50.0

    median = stats[:median]
    if median.positive?
      if listing.price_usd < median
        ratio = (median - listing.price_usd) / median
        score += [ ratio * 100, 30 ].min
      else
        ratio = (listing.price_usd - median) / median
        score -= [ ratio * 50, 20 ].min
      end
    end

    score += listing.condition_bonus
    score += SOURCE_RELIABILITY_BONUS.fetch(listing.source, 0)
    score += listing.spec_bonus

    score = score.clamp(0, 100)
    score = [ score, 10.0 ].min if suspicious?(listing, stats)

    score.round(1)
  end

  def baseline_score(listing)
    if listing.price_usd <= listing.great_deal_price_usd
      90.0
    elsif listing.price_usd <= listing.good_deal_price_usd
      70.0
    else
      40.0
    end
  end

  def suspicious?(listing, stats)
    return false if stats[:median].to_f <= 0 || stats[:count] < SUSPICIOUS_MIN_SAMPLE
    return false if listing.price_usd >= stats[:median] * SUSPICIOUS_PRICE_RATIO

    text = "#{listing.condition} #{listing.title}".downcase
    SUSPICIOUS_CONDITION_KEYWORDS.any? { |kw| text.include?(kw) }
  end
end
