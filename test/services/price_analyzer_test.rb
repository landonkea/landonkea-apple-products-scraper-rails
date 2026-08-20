require "test_helper"

class PriceAnalyzerTest < ActiveSupport::TestCase
  def build_listing(price_usd:, condition: nil, source: "ebay", title: "MacBook Pro 14 M5 Max 128GB")
    Listing.create!(
      source: source, listing_id: SecureRandom.hex(6), title: title, price_usd: price_usd,
      url: "https://example.com/#{SecureRandom.hex(4)}", condition: condition,
      product_type: "electronics", search_name: "MacBook Pro",
      first_seen_at: Time.current, last_seen_at: Time.current
    )
  end

  test "a listing priced well below the batch median scores higher than one at the median" do
    cheap = build_listing(price_usd: 3000)
    median_priced = build_listing(price_usd: 4500)
    pricey = build_listing(price_usd: 6000)

    PriceAnalyzer.call([ cheap, median_priced, pricey ])

    assert_operator cheap.reload.deal_score, :>, median_priced.reload.deal_score
    assert_operator median_priced.deal_score, :>, pricey.reload.deal_score
  end

  test "is_great_deal is set once a listing clears its RAM tier's great-deal threshold" do
    great = build_listing(price_usd: 4500, title: "MacBook Pro 14 M5 Max 128GB RAM")
    great.update!(ram_gb: 128)
    not_great = build_listing(price_usd: 5500, title: "MacBook Pro 14 M5 Max 128GB RAM")
    not_great.update!(ram_gb: 128)

    PriceAnalyzer.call([ great, not_great ])

    assert great.reload.is_great_deal?
    assert_not not_great.reload.is_great_deal?
  end

  test "an implausibly cheap listing claiming to be new/sealed gets flagged and capped, not trusted as a great deal" do
    normal_prices = Array.new(3) { build_listing(price_usd: 4500) }
    suspicious = build_listing(price_usd: 500, condition: "New Sealed")

    PriceAnalyzer.call(normal_prices + [ suspicious ])

    suspicious.reload
    assert_not suspicious.is_great_deal?
    assert suspicious.title.start_with?(PriceAnalyzer::SUSPICIOUS_TAG)
    assert_operator suspicious.deal_score, :<=, 10.0
  end

  test "a genuinely cheap USED listing (no new/sealed wording) is not flagged suspicious" do
    normal_prices = Array.new(3) { build_listing(price_usd: 4500) }
    cheap_but_used = build_listing(price_usd: 2000, condition: "Used")

    PriceAnalyzer.call(normal_prices + [ cheap_but_used ])

    assert_not cheap_but_used.reload.title.start_with?(PriceAnalyzer::SUSPICIOUS_TAG)
  end

  test "meaningful_drop? requires both a percent AND a dollar threshold to be cleared" do
    # $50 off $600 clears both the 5% and $50 bars.
    assert PriceAnalyzer.meaningful_drop?(600.0, 550.0)
    # A big percentage drop on a cheap item that doesn't clear the $50 floor.
    assert_not PriceAnalyzer.meaningful_drop?(60.0, 57.0)
    # A big dollar drop on an expensive item that doesn't clear the 5% floor.
    assert_not PriceAnalyzer.meaningful_drop?(8000.0, 7960.0)
    # A price going UP is never a drop.
    assert_not PriceAnalyzer.meaningful_drop?(4000.0, 4200.0)
    # No prior price at all -- nothing to compare against.
    assert_not PriceAnalyzer.meaningful_drop?(nil, 4000.0)
  end

  test "an empty batch produces zeroed stats instead of raising" do
    PriceAnalyzer.call([])
    stats = PriceAnalyzer.new([]).stats
    assert_equal 0, stats[:count]
  end
end
