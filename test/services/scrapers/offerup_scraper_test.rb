require "test_helper"

module Scrapers
  class OfferupScraperTest < ActiveSupport::TestCase
    test "reads listings out of the __NEXT_DATA__ JSON blob" do
      next_data = {
        props: {
          pageProps: {
            searchFeedResponse: {
              looseTiles: [
                {
                  "__typename" => "ModularFeedTileListing",
                  "listing" => {
                    "listingId" => "off-778899",
                    "title" => "MacBook Pro 14 M5 Max 128GB 2TB",
                    "price" => { "value" => 4150.0 },
                    "condition" => "Used",
                    "location" => "Phoenix, AZ"
                  }
                }
              ]
            }
          }
        }
      }.to_json
      html = "<html><script id=\"__NEXT_DATA__\">#{next_data}</script></html>"

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      scraper = OfferupScraper.new(search)
      scraper.define_singleton_method(:fetch_rendered) { |*_args, **_kwargs| html }

      results = scraper.scrape

      assert_equal 1, results.length
      assert_equal "offerup", results.first[:source]
      assert_equal "off-778899", results.first[:listing_id]
      assert_equal 4150.0, results.first[:price_usd]
    end

    test "falls back to scanning rendered cards when __NEXT_DATA__ is missing" do
      html = <<~HTML
        <div data-testid="search-card">
          <a href="/item/detail/off-445566">
            <span class="title">MacBook Pro 14 M5 Max 128GB 2TB</span>
            <span class="price">$3,999</span>
          </a>
        </div>
      HTML

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      scraper = OfferupScraper.new(search)
      scraper.define_singleton_method(:fetch_rendered) { |*_args, **_kwargs| html }

      results = scraper.scrape

      assert_equal 1, results.length
      assert_equal "off-445566", results.first[:listing_id]
    end
  end
end
