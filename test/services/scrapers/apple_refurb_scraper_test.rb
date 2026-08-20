require "test_helper"

module Scrapers
  class AppleRefurbScraperTest < ActiveSupport::TestCase
    test "parses the embedded REFURB_GRID_BOOTSTRAP JSON blob" do
      bootstrap = {
        tiles: [
          {
            title: "Apple MacBook Pro 14-inch M5 Max 128GB",
            productDetailsUrl: "/shop/product/ABC123",
            price: { currentPrice: { raw_amount: 3999.0 } },
            filters: { dimensions: { refurbClearModel: [ "macbookpro" ] } }
          }
        ]
      }.to_json
      html = "<html><script>window.REFURB_GRID_BOOTSTRAP = #{bootstrap};</script></html>"

      stub_request(:get, "https://www.apple.com/shop/refurbished/mac/14-inch-macbook-pro").to_return(status: 200, body: html)
      stub_request(:get, "https://www.apple.com/shop/refurbished/mac/16-inch-macbook-pro").to_return(status: 200, body: "<html></html>")

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      results = AppleRefurbScraper.new(search).scrape

      assert_equal 1, results.length
      assert_equal "apple_refurb", results.first[:source]
      assert_equal 3999.0, results.first[:price_usd]
      assert_equal "Refurbished", results.first[:condition]
      assert_equal "https://www.apple.com/shop/product/ABC123", results.first[:url]
    end
  end
end
