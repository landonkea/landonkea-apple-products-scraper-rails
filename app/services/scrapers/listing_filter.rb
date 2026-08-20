# Every scraper needs to run the exact same filtering pass on whatever
# raw listing it just parsed off a marketplace page: reject it for
# being an accessory/off-topic listing, reject it for not matching
# this search's specs (chip, RAM, storage, weight capacity, whatever
# applies), or reject it for being priced outside our range. Pulling
# this into one shared helper means every scraper applies identical
# rules instead of each reimplementing (and risking drifting from) the
# same checks. A port of Python's `BaseScraper#passes_filters`, which
# every scraper subclass called at the end of its own parsing.
module Scrapers
  class ListingFilter
    # Below this, a stated weight capacity is a hard reject -- not
    # safe for the rider this search is specced for. Matches ebike.py's
    # MIN_ACCEPTABLE_WEIGHT_CAPACITY_LB.
    MIN_ACCEPTABLE_WEIGHT_CAPACITY_LB = 330

    # `passes?` takes the raw fields a scraper just parsed off a
    # listing card plus the already-extracted spec hash (from
    # SpecParser.parse_electronics/parse_ebike) and the active search
    # hash, and returns true only if the listing survives every check.
    def self.passes?(title:, condition:, price_usd:, location:, parsed:, search:)
      if search[:product_type] == :ebike
        return false unless SpecParser.ebike_relevant?(title, condition)
        return false unless ebike_type_filters_pass?(parsed, search)
      else
        return false unless SpecParser.electronics_relevant?(title, condition, search[:product_name])
        return false unless electronics_type_filters_pass?(title, parsed, search)
      end

      return false if search[:location] && location && !location.downcase.include?(search[:location].downcase)
      return false if price_usd < Listing.min_price_usd(search[:product_name], search[:product_type].to_s)
      return false if price_usd > Listing::ABSOLUTE_MAX_PRICE_USD

      true
    end

    # A direct port of electronics.py's
    # ElectronicsHandler#passes_type_filters -- every check here is
    # skipped (not enforced) when the corresponding search field isn't
    # set, so loosening a search's requirements is a config edit, not
    # a code change.
    def self.electronics_type_filters_pass?(title, parsed, search)
      if search[:chip_options].present?
        return false if parsed[:chip].blank?
        chip_lower = parsed[:chip].downcase
        return false unless search[:chip_options].any? { |option| chip_lower.include?(option.downcase) }
      end

      if search[:model_keywords].present?
        title_lower = title.downcase
        return false unless search[:model_keywords].any? { |kw| title_lower.include?(kw.downcase) }
      end

      if search[:screen_sizes].present? && parsed[:screen_size].present?
        size_ok = search[:screen_sizes].any? { |size| (parsed[:screen_size] - size).abs < 1.0 }
        return false unless size_ok
      end

      if search[:ram_gb_primary].present? && parsed[:ram_gb].present?
        ram_ok = parsed[:ram_gb] == search[:ram_gb_primary] || parsed[:ram_gb] == search[:ram_gb_fallback]
        return false unless ram_ok
      end

      if search[:storage_gb_min].present? && parsed[:storage_gb].present?
        return false if parsed[:storage_gb] < search[:storage_gb_min]
      end
      if search[:storage_gb_max].present? && parsed[:storage_gb].present?
        return false if parsed[:storage_gb] > search[:storage_gb_max]
      end

      if search[:cellular]
        return false unless title.downcase.match?(/cellular|5g|lte/)
      end

      true
    end

    # A direct port of ebike.py's EbikeHandler#passes_type_filters --
    # the ONLY hard filter is weight capacity, and only when the title
    # actually states one. Everything else about an e-bike listing is a
    # scoring bonus (see Listing#ebike_spec_bonus), never a pass/fail
    # gate, since nearly every e-bike spec here comes from imperfect
    # title parsing rather than a structured field.
    def self.ebike_type_filters_pass?(parsed, search)
      cap = parsed[:weight_capacity_lb]
      return true if cap.nil?

      floor = search[:min_weight_capacity_lb] || MIN_ACCEPTABLE_WEIGHT_CAPACITY_LB
      cap >= floor
    end
  end
end
