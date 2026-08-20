require "test_helper"

module Scrapers
  class SwappaScraperTest < ActiveSupport::TestCase
    test "discovers a product slug from the category page, then parses its listing cards" do
      category_html = <<~HTML
        <div class="card card_product">
          <div class="card-title title">MacBook Pro 14 M5 Max 128GB</div>
          <meta itemprop="sku" content="macbook-pro-14-m5-max-128">
        </div>
      HTML
      listing_html = <<~HTML
        <div class="card xui_card xui_card_listing">
          <img alt="MacBook Pro 14 M5 Max 128GB 2TB">
          <div class="price"><span itemprop="price">4599.00</span><a href="/listings/abc123">view</a></div>
          <span class="code ms-2">SWP-ABC123</span>
          <div class="ships_from">CA</div>
          <div class="attrs"><span class="attr">Excellent</span><span class="attr">128GB</span></div>
        </div>
      HTML

      stub_request(:get, "https://swappa.com/buy/macbooks/macbook-pro?sort=price_asc").to_return(status: 200, body: category_html)
      stub_request(:get, "https://swappa.com/listings/macbook-pro-14-m5-max-128").to_return(status: 200, body: listing_html)

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      results = SwappaScraper.new(search).scrape

      assert_equal 1, results.length
      assert_equal "swappa", results.first[:source]
      assert_equal "SWP-ABC123", results.first[:listing_id]
      assert_equal 4599.00, results.first[:price_usd]
      assert_equal "Excellent", results.first[:condition]
    end
  end
end
