require "test_helper"

module Scrapers
  class GazelleScraperTest < ActiveSupport::TestCase
    test "fetches a Shopify collection per model_keyword and flattens available variants" do
      products_json = {
        products: [
          {
            title: "iPhone 17 Pro Max 1TB",
            handle: "iphone-17-pro-max",
            variants: [
              { id: 1, price: "899.00", option2: "Excellent", available: true },
              { id: 2, price: "1099.00", option2: "Good", available: false }
            ]
          }
        ]
      }.to_json

      %w[iphone-17-pro-max iphone-16-pro-max iphone-15-pro-max].each do |handle|
        body = handle == "iphone-17-pro-max" ? products_json : { products: [] }.to_json
        stub_request(:get, "https://buy.gazelle.com/collections/#{handle}/products.json?limit=250")
          .to_return(status: 200, body: body)
      end

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "iPhone Pro Max" }
      results = GazelleScraper.new(search).scrape

      # Only the available: true variant should come back.
      assert_equal 1, results.length
      assert_equal "gazelle", results.first[:source]
      assert_equal "gazelle-1", results.first[:listing_id]
      assert_equal 899.0, results.first[:price_usd]
      assert_equal "Excellent", results.first[:condition]
    end
  end
end
