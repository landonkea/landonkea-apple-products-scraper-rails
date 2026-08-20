require "test_helper"

class PriceHistoryTest < ActiveSupport::TestCase
  test "requires a positive price and a recorded_at" do
    history = PriceHistory.new(listing: listings(:macbook_pro_ebay))
    assert_not history.valid?
    assert_includes history.errors.attribute_names, :price_usd
    assert_includes history.errors.attribute_names, :recorded_at

    history.price_usd = -5
    history.recorded_at = Time.current
    assert_not history.valid?
  end

  test "chronological orders oldest first" do
    listing = listings(:macbook_pro_ebay)
    ordered = listing.price_histories.chronological.to_a
    assert_equal ordered, ordered.sort_by(&:recorded_at)
  end

  test "record_if_changed! writes a new row when the price actually changed" do
    listing = listings(:macbook_pro_ebay)

    assert_difference "listing.price_histories.count", 1 do
      assert PriceHistory.record_if_changed!(listing, 3999.0)
    end
  end

  test "record_if_changed! writes nothing when the price is identical to the last recorded point" do
    listing = listings(:macbook_pro_ebay)
    last_price = listing.price_histories.chronological.last.price_usd

    assert_no_difference "listing.price_histories.count" do
      assert_not PriceHistory.record_if_changed!(listing, last_price)
    end
  end
end
