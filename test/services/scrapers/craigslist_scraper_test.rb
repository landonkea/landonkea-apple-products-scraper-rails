require "test_helper"

module Scrapers
  class CraigslistScraperTest < ActiveSupport::TestCase
    test "parses real listing cards and filters out non-matching specs" do
      html = <<~HTML
        <ol class="cl-static-search-results">
          <li class="cl-static-search-result" href="https://phoenix.craigslist.org/evl/sys/1111111111.html">
            <div class="title">MacBook Pro 14 M5 Max 128GB 2TB</div>
            <div class="price">$4200</div>
            <div class="location">Tempe</div>
          </li>
          <li class="cl-static-search-result" href="https://phoenix.craigslist.org/evl/sys/2222222222.html">
            <div class="title">MacBook Pro Case Sleeve</div>
            <div class="price">$25</div>
            <div class="location">Mesa</div>
          </li>
        </ol>
      HTML

      stub_request(:get, /craigslist\.org\/search\/area\/phoenix/).to_return(status: 200, body: html)

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      results = CraigslistScraper.new(search).scrape

      assert_equal 1, results.length
      assert_equal "craigslist", results.first[:source]
      assert_equal "craigslist-1111111111", results.first[:listing_id]
      assert_equal 4200.0, results.first[:price_usd]
      assert_equal "Tempe", results.first[:location]
    end
  end
end
