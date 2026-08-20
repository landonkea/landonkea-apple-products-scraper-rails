require "test_helper"

module Scrapers
  class BestbuyScraperTest < ActiveSupport::TestCase
    test "keeps only cards with a genuine Open Box badge" do
      html = <<~HTML
        <li class="product-list-item" data-product-id="6543210">
          <h3 class="product-title">MacBook Pro 14 M5 Max 128GB 2TB</h3>
          <a class="product-list-item-link" href="/site/macbook-pro/6543210.p">view</a>
          <span data-testid="price-block-badging-text">Open Box</span>
          <div data-testid="price-block-customer-price"><span class="font-500">$4,099.99</span></div>
        </li>
        <li class="product-list-item" data-product-id="1112223">
          <h3 class="product-title">MacBook Pro 14 M5 Max 128GB 2TB - New Sealed</h3>
          <a class="product-list-item-link" href="/site/macbook-pro/1112223.p">view</a>
          <div data-testid="price-block-customer-price"><span class="font-500">$4,299.99</span></div>
        </li>
      HTML

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      scraper = BestbuyScraper.new(search)
      scraper.define_singleton_method(:fetch_rendered) { |*_args, **_kwargs| html }

      results = scraper.scrape

      assert_equal 1, results.length
      assert_equal "6543210", results.first[:listing_id]
      assert_equal "Open Box", results.first[:condition]
    end
  end
end
