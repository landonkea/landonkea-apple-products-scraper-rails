# A Listing is one product for sale on one marketplace -- an eBay
# result, a Swappa result, a Craigslist post, and so on. Scrapers write
# these, PriceAnalyzer scores them, and the dashboard reads them back.
# The same table holds two very different kinds of product (Apple
# hardware and e-bikes) -- product_type says which one, and decides
# which of the two spec_bonus branches below actually runs.
class Listing < ApplicationRecord
  # One listing can have many recorded price points over its lifetime
  # -- destroy them too if the listing itself is ever deleted, so we
  # never leave orphaned history rows behind.
  has_many :price_histories, dependent: :destroy

  # No listing this scraper saves is worth looking at above this price
  # -- matches config.yaml's price.absolute_max_usd in the Python
  # version, a single shared ceiling across every search.
  ABSOLUTE_MAX_PRICE_USD = 8_000

  # How many of the best-scoring listings from one search go into a
  # single Discord alert -- matches config.yaml's price.top_deals_count,
  # trimmed down from the Python default of 40 since that many fields
  # in one alert is more than a person actually reads.
  TOP_DEALS_COUNT = 15

  # ── "Great deal" / "good deal" price ceilings ───────────────────────
  # Keyed by whatever PriceAnalyzer's threshold_key returns for a given
  # listing: ram_gb for MacBook Pro (128/64), storage_gb for iPhone Pro
  # Max (1024 = 1TB, 2048 = 2TB) and iPad Pro (falls back to ram_gb 16
  # first), or the literal string "ebike" when neither ram_gb nor
  # storage_gb is set at all. A straight port of config.yaml's
  # price.great_deal_usd / price.good_deal_usd, with the iPhone 1TB/2TB
  # tiers added in (the Python config never actually defined a
  # storage-keyed threshold for iPhone, so those listings silently fell
  # back to a $5,000 default there -- this port gives iPhone its own
  # researched thresholds instead of carrying that gap forward).
  GREAT_DEAL_USD = {
    128 => 5_000,   # MacBook Pro 128GB
    64 => 4_000,    # MacBook Pro 64GB
    16 => 900,      # iPad Pro 16GB
    1024 => 900,    # iPhone Pro Max 1TB (used market, researched)
    2048 => 1_100,  # iPhone Pro Max 2TB (used market, researched)
    "ebike" => 900  # folding step-through e-bike
  }.freeze

  GOOD_DEAL_USD = {
    128 => 5_500,
    64 => 4_500,
    16 => 1_000,
    1024 => 1_050,
    2048 => 1_300,
    "ebike" => 1_300
  }.freeze

  # The floor below which a listing is almost certainly an accessory or
  # a typo, not a real product -- varies by what's actually being
  # searched for. A direct port of electronics.py's
  # MINIMUM_PRICE_USD/MINIMUM_IPHONE_PRICE_USD and ebike.py's
  # MINIMUM_PRICE_USD.
  def self.min_price_usd(search_name, product_type)
    return 300 if product_type == "ebike"
    return 100 if search_name.include?("iPhone")
    return 500 if search_name.include?("iPad")

    200 # MacBook Pro and anything else electronics-shaped
  end

  # Every real listing needs these five things to make any sense at
  # all -- a source marketplace, the marketplace's own id for it, a
  # title, a price, and a link. Rails checks these before saving.
  validates :source, presence: true
  validates :listing_id, presence: true
  validates :title, presence: true
  validates :price_usd, presence: true, numericality: { greater_than: 0 }
  validates :url, presence: true
  # The same marketplace can never report the same listing_id twice --
  # this mirrors the database-level unique index from the migration,
  # so a duplicate attempt fails with a friendly validation error
  # instead of a raw SQL exception.
  validates :listing_id, uniqueness: { scope: :source }

  # deal_score_breakdown is never saved to the database -- it's only
  # useful for the few seconds between "PriceAnalyzer just scored this
  # listing" and "the Discord notifier just built an alert from it," so
  # there's no reason to add a column and a migration for it. attr_accessor
  # gives the object a plain in-memory place to hold it for that window.
  attr_accessor :deal_score_breakdown

  # Same idea as deal_score_breakdown above -- "how much cheaper is this
  # than Apple's own refurb price for the same config" is only ever
  # needed for the alert sent right after scoring, so it's a runtime-only
  # attribute rather than a database column.
  attr_accessor :apple_refurb_price
  attr_accessor :vs_apple_refurb_pct

  # Only listings we've seen recently (not yet expired after 72 hours
  # of silence) count as "currently for sale" on the dashboard.
  scope :active, -> { where(is_active: true) }

  # The dashboard's default sort -- best deals (highest score) first.
  # Listings that were never scored (deal_score is nil) sort last.
  scope :best_deals_first, -> { order(Arel.sql("deal_score IS NULL, deal_score DESC")) }

  # Lets the dashboard's marketplace filter do Listing.from_source("ebay").
  scope :from_source, ->(source) { where(source: source) if source.present? }

  # Lets the dashboard's product filter do Listing.for_search("MacBook Pro").
  scope :for_search, ->(search_name) { where(search_name: search_name) if search_name.present? }

  # Only listings flagged as a genuinely great price (below the
  # configured great_deal threshold for their spec tier).
  scope :great_deals, -> { where(is_great_deal: true) }

  # A quick, human-readable label for the price-history page and any
  # log lines -- keeps "$1,234 | ebay | MacBook Pro 14..." out of every
  # view/controller that wants to describe a listing briefly.
  def short_label
    "$#{price_usd.to_i} | #{source} | #{title.to_s.truncate(60)}"
  end

  # Which key this listing's price gets compared against in
  # GREAT_DEAL_USD / GOOD_DEAL_USD above -- RAM first (MacBook Pro),
  # then storage (iPhone Pro Max), then falling all the way back to the
  # product_type string itself for a product with neither (e-bikes). A
  # port of Python's PriceAnalyzer._threshold_key, see that method's
  # docstring for the full reasoning.
  def threshold_key
    ram_gb || storage_gb || product_type
  end

  def great_deal_price_usd
    GREAT_DEAL_USD.fetch(threshold_key, 5_000)
  end

  def good_deal_price_usd
    GOOD_DEAL_USD.fetch(threshold_key, 5_500)
  end

  # A small nudge for the marketplace's own condition label -- "New" or
  # "Certified Refurbished" is worth more than a bare "Good", and an
  # ungraded/unknown condition (very common on Craigslist) earns
  # nothing either way. Applies the same regardless of product_type,
  # matching how price_analyzer.py's condition check in the Python
  # version was never product-type-specific either.
  def condition_bonus
    return 0.0 if condition.blank?

    lower = condition.downcase
    if lower.include?("new") || lower.include?("certified") || lower.include?("refurbished")
      5.0
    elsif lower.include?("open") || lower.include?("excellent")
      3.0
    elsif lower.include?("good")
      1.0
    else
      0.0
    end
  end

  # Category-specific scoring on top of the universal price/condition/
  # source factors PriceAnalyzer already applies -- dispatches on
  # product_type the same way Python's PRODUCT_TYPES[product_type]
  # lookup did, just as a plain if/else instead of a registered handler
  # class, since this app only ever has the two categories.
  def spec_bonus
    product_type == "ebike" ? ebike_spec_bonus : electronics_spec_bonus
  end

  private

  # A direct port of electronics.py's ElectronicsHandler#score_bonuses.
  # chip_generation_map/core_count_reference aren't carried over here
  # (see README) -- this app tracks a fixed window of chip names per
  # search instead of a generic generation map, so the "how many
  # generations back is this" bonus below reads straight off that list.
  def electronics_spec_bonus
    bonus = 0.0

    # RAM tier -- the primary configured amount is worth more than the
    # fallback amount, matches Python's ram_gb_primary/ram_gb_fallback.
    search = ScrapeRunner.search_for(search_name)
    if search
      bonus += 10 if ram_gb.present? && ram_gb == search[:ram_gb_primary]
      bonus += 2 if ram_gb.present? && ram_gb == search[:ram_gb_fallback]

      # Chip generation -- the newest tracked chip in this search's
      # window scores highest, tapering off for older ones, matches
      # Python's "newest +8, next +5, oldest +2" tapering exactly.
      if chip.present? && search[:chip_options].present?
        index = search[:chip_options].index { |option| chip.downcase.include?(option.downcase) }
        bonus += [ 8 - (3 * index), 0 ].max if index
      end

      # Screen size preference -- earlier entries in screen_sizes are
      # preferred (14" over 16"), matches Python's "1st +3, 2nd +1" taper.
      if screen_size.present? && search[:screen_sizes].present?
        index = search[:screen_sizes].index { |size| (screen_size - size).abs < 1.0 }
        bonus += [ 3 - (2 * index), 0 ].max if index
      end
    end

    # Core count -- a small reward for stating the flagship CPU/GPU
    # core-count bin, most listings just don't mention this at all.
    bonus += 4 if cpu_cores.present? && gpu_cores.present? && cpu_cores >= 14 && gpu_cores >= 30

    # Storage -- bigger is better, but this matters least of all,
    # capped at +3 for an 8TB drive, matches Python exactly.
    bonus += [ storage_gb.to_f / 8_192 * 3, 3 ].min if storage_gb.present?

    bonus
  end

  # A direct port of ebike.py's EbikeHandler#score_bonuses -- see that
  # module's docstring for the full "safety > capacity > step-through >
  # battery > ..." priority order this weighting follows.
  def ebike_spec_bonus
    bonus = 0.0

    bonus += 12 if ul_certified

    if weight_capacity_lb.present?
      bonus += if weight_capacity_lb >= 400
        15
      elsif weight_capacity_lb >= 350
        10
      elsif weight_capacity_lb >= 330
        3
      else
        0
      end
    end

    bonus += 10 if step_through

    if battery_ah.present?
      bonus += if battery_ah >= 20
        10
      elsif battery_ah >= 15
        7
      elsif battery_ah >= 13
        4
      elsif battery_ah >= 10
        1
      else
        0
      end
    end
    bonus += 4 if battery_voltage == 48
    bonus += 1 if battery_voltage && battery_voltage >= 36 && battery_voltage != 48
    bonus += 3 if title.to_s.downcase.include?("removable")

    if motor_watts_nominal.present?
      bonus += if motor_watts_nominal.between?(700, 850)
        6
      elsif motor_watts_nominal.between?(500, 1000)
        3
      else
        0
      end
    end
    bonus += 3 if motor_watts_peak.present? && motor_watts_peak >= 1200

    bonus += 5 if [ 16.0, 20.0, 24.0 ].include?(wheel_size_in)
    bonus += 3 if fat_tire

    case brake_type
    when "hydraulic" then bonus += 5
    when "mechanical" then bonus += 2
    when "rim" then bonus -= 3
    end
    bonus += 3 if suspension

    bonus += 6 if folding

    # Reuses SpecParser::EBIKE_KNOWN_BRANDS as the "preferred brand"
    # list rather than threading the active search's preferred_brands
    # array through the model -- in practice every brand a listing can
    # have here already came from that same known-brand list (see
    # SpecParser.extract_ebike_brand), so this is equivalent to Python's
    # "brand is in search.preferred_brands" check without needing the
    # model to know about the active search's config.
    bonus += 4 if brand.present?

    bonus
  end
end
