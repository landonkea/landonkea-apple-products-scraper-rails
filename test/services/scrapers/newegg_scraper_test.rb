require "test_helper"

module Scrapers
  class NeweggScraperTest < ActiveSupport::TestCase
    test "parses price split across strong/sup tags and an open-box badge" do
      html = <<~HTML
        <div class="item-cell">
          <a class="item-title" href="https://www.newegg.com/p/N82E1683">MacBook Pro 14 M5 Max 128GB 2TB</a>
          <li class="price-current"><strong>4,199</strong><sup>.00</sup></li>
          <span class="item-open-box-italic">Open Box</span>
        </div>
      HTML

      stub_request(:get, /newegg\.com\/p\/pl\?d=.*&page=1\z/).to_return(status: 200, body: html)
      # No further cards on later pages -- return an empty grid.
      stub_request(:get, /newegg\.com\/p\/pl\?d=.*&page=[2-5]\z/).to_return(status: 200, body: "<html></html>")

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      results = NeweggScraper.new(search).scrape

      assert_equal 1, results.length
      assert_equal "newegg", results.first[:source]
      assert_equal 4199.00, results.first[:price_usd]
      assert_equal "Open Box", results.first[:condition]
    end
  end
end
