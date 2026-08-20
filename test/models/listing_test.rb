require "test_helper"

class ListingTest < ActiveSupport::TestCase
  test "requires the core fields every listing needs" do
    listing = Listing.new
    assert_not listing.valid?
    assert_includes listing.errors.attribute_names, :source
    assert_includes listing.errors.attribute_names, :listing_id
    assert_includes listing.errors.attribute_names, :title
    assert_includes listing.errors.attribute_names, :price_usd
    assert_includes listing.errors.attribute_names, :url
  end

  test "the same source can never report the same listing_id twice" do
    dupe = listings(:macbook_pro_ebay).dup
    dupe.assign_attributes(product_type: "electronics", first_seen_at: Time.current, last_seen_at: Time.current)
    assert_not dupe.valid?
    assert_includes dupe.errors[:listing_id], "has already been taken"
  end

  test "threshold_key prefers ram_gb, then storage_gb, then falls back to product_type" do
    macbook = listings(:macbook_pro_ebay)
    assert_equal 128, macbook.threshold_key

    macbook.update!(ram_gb: nil, storage_gb: 1024)
    assert_equal 1024, macbook.threshold_key

    macbook.update!(storage_gb: nil)
    assert_equal "electronics", macbook.threshold_key
  end

  test "great_deal_price_usd and good_deal_price_usd read off the RAM tier" do
    macbook = listings(:macbook_pro_ebay)
    assert_equal 5_000, macbook.great_deal_price_usd
    assert_equal 5_500, macbook.good_deal_price_usd
  end

  test "an e-bike listing's threshold falls back to the product_type string" do
    bike = listings(:ebike_offerup)
    assert_equal "ebike", bike.threshold_key
    assert_equal 900, bike.great_deal_price_usd
    assert_equal 1_300, bike.good_deal_price_usd
  end

  test "condition_bonus rewards new/refurbished over a bare good, and blank earns nothing" do
    listing = listings(:macbook_pro_ebay)

    listing.condition = "Certified Refurbished"
    assert_equal 5.0, listing.condition_bonus

    listing.condition = "Excellent"
    assert_equal 3.0, listing.condition_bonus

    listing.condition = "Good"
    assert_equal 1.0, listing.condition_bonus

    listing.condition = nil
    assert_equal 0.0, listing.condition_bonus
  end

  test "electronics_spec_bonus rewards the primary RAM tier over the fallback" do
    macbook = listings(:macbook_pro_ebay)
    primary_bonus = macbook.spec_bonus

    macbook.ram_gb = 64 # the configured fallback tier for MacBook Pro
    fallback_bonus = macbook.spec_bonus

    assert primary_bonus > fallback_bonus
  end

  test "ebike_spec_bonus rewards a hydraulic brake over a rim brake" do
    bike = listings(:ebike_offerup)
    bike.brake_type = "hydraulic"
    hydraulic_bonus = bike.spec_bonus

    bike.brake_type = "rim"
    rim_bonus = bike.spec_bonus

    assert hydraulic_bonus > rim_bonus
  end

  test "min_price_usd differs by product and product_type" do
    assert_equal 200, Listing.min_price_usd("MacBook Pro", "electronics")
    assert_equal 100, Listing.min_price_usd("iPhone Pro Max", "electronics")
    assert_equal 500, Listing.min_price_usd("iPad Pro", "electronics")
    assert_equal 300, Listing.min_price_usd("Folding step-through commuter e-bike", "ebike")
  end

  test "active/from_source/for_search/great_deals scopes filter as expected" do
    assert_includes Listing.active, listings(:macbook_pro_ebay)
    assert_includes Listing.from_source("ebay"), listings(:macbook_pro_ebay)
    assert_not_includes Listing.from_source("ebay"), listings(:ebike_offerup)
    assert_includes Listing.for_search("MacBook Pro"), listings(:macbook_pro_ebay)
    assert_includes Listing.great_deals, listings(:macbook_pro_ebay)
    assert_not_includes Listing.great_deals, listings(:ebike_offerup)
  end

  test "best_deals_first orders highest score to lowest, nil scores last" do
    unscored = Listing.create!(
      source: "craigslist", listing_id: "unscored-1", title: "MacBook Pro 14 M5 Max",
      price_usd: 4000.0, url: "https://example.com", product_type: "electronics",
      search_name: "MacBook Pro", first_seen_at: Time.current, last_seen_at: Time.current
    )

    ordered = Listing.best_deals_first.to_a
    assert_operator ordered.index(listings(:macbook_pro_ebay)), :<, ordered.index(unscored)
  end
end
