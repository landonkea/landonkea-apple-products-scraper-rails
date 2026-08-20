# This migration builds the "listings" table -- every row in it is one
# product we found for sale on one marketplace (an eBay listing, a Swappa
# listing, and so on). This is the single most important table in the
# whole app: the dashboard reads from it, the price scorer writes to it,
# and the Discord alerts are built from it.
class CreateListings < ActiveRecord::Migration[8.1]
  def change
    # create_table :listings do |t| ... end is Rails' way of saying
    # "build a table named listings, and here are its columns."
    create_table :listings do |t|
      # Which marketplace this came from, e.g. "ebay", "swappa", "craigslist".
      # null: false means every row MUST have one (a listing with no known
      # source makes no sense), and index: true makes "show me all eBay
      # listings" a fast lookup instead of a full table scan.
      t.string :source, null: false, index: true

      # The marketplace's OWN id for this exact listing (their item number,
      # not ours). Combined with source below, this is how we recognize
      # "oh, we've already seen this one" on the next scrape.
      t.string :listing_id, null: false

      # The full listing title exactly as the marketplace wrote it, e.g.
      # 'Apple MacBook Pro 14" M5 Max 128GB 2TB - Space Black'.
      t.string :title, null: false

      # The price in US dollars, stored as a plain number (not a string)
      # so we can sort/compare/average it. Indexed because "cheapest
      # first" is one of the dashboard's main sort options.
      t.float :price_usd, null: false, index: true

      # Almost always "USD" -- kept as its own column (with a default,
      # so we never have to pass it explicitly) in case a future
      # marketplace ever lists in another currency.
      t.string :currency, null: false, default: "USD"

      # The actual clickable link to the listing on the marketplace's site.
      # text (not string) because URLs can run long with tracking params.
      t.text :url, null: false

      # The marketplace's own condition label, e.g. "New", "Used",
      # "Certified Refurbished". Can be blank -- some sites (Craigslist,
      # Mercari) never expose a structured condition at all.
      t.string :condition

      # ── Specs pulled out of the title by regex, MacBook/iPhone/iPad ──
      # These are all optional (a boot or e-bike listing has none of them)
      # -- that's why none of them get null: false.
      t.integer :ram_gb          # e.g. 128 for a 128GB MacBook Pro
      t.integer :storage_gb      # in GB, e.g. 2048 for a 2TB drive
      t.float :screen_size       # in inches, e.g. 14.0
      t.string :chip             # e.g. "M5 Max"
      t.integer :cpu_cores       # e.g. 16
      t.integer :gpu_cores       # e.g. 40

      # ── Specs pulled out of the title for the e-bike search ──────────
      # Also all optional -- a MacBook listing leaves every one of these
      # blank, same table, two very different kinds of "product" in it.
      t.string :brand                  # e.g. "Lectric", "Aventon"
      t.float :wheel_size_in           # wheel diameter, e.g. 20.0
      t.boolean :fat_tire               # true if the title mentions a fat tire
      t.boolean :step_through           # title-keyword signal only, see EbikeScorer
      t.boolean :folding                 # true if the frame folds up
      t.integer :battery_voltage        # e.g. 48
      t.float :battery_ah                # battery amp-hours, e.g. 20.0
      t.float :battery_wh                # voltage * amp-hours, when both are known
      t.integer :motor_watts_nominal    # the "everyday" motor power rating
      t.integer :motor_watts_peak       # the short-burst maximum, only when the title says "peak"
      t.integer :weight_capacity_lb     # manufacturer's stated rider/load limit
      t.string :brake_type               # "hydraulic" / "mechanical" / "rim"
      t.boolean :suspension              # true if the title mentions front suspension
      t.boolean :ul_certified            # true if the title claims UL safety certification

      # ── Deal scoring, computed after every scrape ─────────────────────
      # A 0-100 number where higher means "better deal" -- see
      # app/services/price_analyzer.rb for exactly how this is calculated.
      t.float :deal_score
      # true once this listing's price falls under our "great deal"
      # threshold for its spec tier -- this is what triggers a Discord alert.
      t.boolean :is_great_deal, null: false, default: false

      # ── Timestamps we control ourselves (separate from Rails' own
      # created_at/updated_at below, which track row-edit history, not
      # "when did we first/last see this on the marketplace") ──────────
      t.datetime :first_seen_at, null: false   # the first scrape that ever found this listing
      t.datetime :last_seen_at, null: false, index: true  # the most recent scrape that still saw it

      # false once we've gone 72+ hours without seeing this listing
      # again (it's probably sold or taken down). We never delete the
      # row -- just stop showing it on the "current deals" dashboard.
      t.boolean :is_active, null: false, default: true, index: true

      # Which ProductTypeHandler scored this listing -- "electronics" or
      # "ebike" -- so the dashboard and the scorer both know which rules
      # applied without having to re-guess from the title.
      t.string :product_type, null: false, index: true

      # Which configured search produced this listing, e.g. "MacBook Pro"
      # or "Folding step-through commuter e-bike" -- powers the dashboard's
      # "filter by product" dropdown.
      t.string :search_name, null: false, index: true

      # Adds created_at/updated_at columns Rails maintains automatically
      # on every insert/update, standard bookkeeping every table gets.
      t.timestamps
    end

    # A listing is uniquely identified by (source, listing_id) together --
    # "ebay" listing #12345 and "swappa" listing #12345 are two different
    # products that just happen to share a number. This index both makes
    # duplicate-lookup fast AND stops the database from ever accepting a
    # true duplicate row, even if our own upsert code has a bug.
    add_index :listings, [ :source, :listing_id ], unique: true, name: "index_listings_on_source_and_listing_id"
  end
end
