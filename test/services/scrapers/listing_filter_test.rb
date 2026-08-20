require "test_helper"

module Scrapers
  class ListingFilterTest < ActiveSupport::TestCase
    def electronics_search
      ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
    end

    def ebike_search
      ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "Folding step-through commuter e-bike" }
    end

    test "rejects an electronics listing priced above the absolute ceiling" do
      title = "MacBook Pro 14 M5 Max 128GB 2TB"
      parsed = SpecParser.parse_electronics(title)

      refute ListingFilter.passes?(
        title: title, condition: nil, price_usd: 9_000.0, location: nil,
        parsed: parsed, search: electronics_search
      )
    end

    test "rejects an electronics listing below its category's accessory-price floor" do
      title = "MacBook Pro 14 M5 Max 128GB 2TB"
      parsed = SpecParser.parse_electronics(title)

      refute ListingFilter.passes?(
        title: title, condition: nil, price_usd: 50.0, location: nil,
        parsed: parsed, search: electronics_search
      )
    end

    test "an e-bike listing with a stated capacity under 330lb is hard-rejected" do
      title = "Lectric Folding E-Bike 250lb capacity"
      parsed = SpecParser.parse_ebike(title)

      refute ListingFilter.passes?(
        title: title, condition: nil, price_usd: 900.0, location: nil,
        parsed: parsed, search: ebike_search
      )
    end

    test "an e-bike listing that never states a capacity at all is NOT rejected" do
      title = "Lectric Folding E-Bike 48V 20Ah"
      parsed = SpecParser.parse_ebike(title)

      assert ListingFilter.passes?(
        title: title, condition: nil, price_usd: 900.0, location: nil,
        parsed: parsed, search: ebike_search
      )
    end
  end
end
