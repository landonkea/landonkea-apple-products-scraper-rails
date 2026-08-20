require "test_helper"

module Scrapers
  class BackmarketScraperTest < ActiveSupport::TestCase
    test "parses rendered product cards into candidates" do
      html = <<~HTML
        <article data-spec="product-card-content">
          <a href="/en-us/p/macbook-pro-14-m5-max-128gb/abc-123">MacBook Pro 14 M5 Max 128GB 2TB</a>
          <span data-test="price">$4,499.00</span>
        </article>
      HTML

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      scraper = BackmarketScraper.new(search)
      scraper.define_singleton_method(:fetch_rendered) { |*_args, **_kwargs| html }

      results = scraper.scrape

      assert_equal 1, results.length
      assert_equal "backmarket", results.first[:source]
      assert_equal 4499.00, results.first[:price_usd]
      assert_equal "abc-123", results.first[:listing_id]
    end
  end
end
