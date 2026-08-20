require "test_helper"

module Scrapers
  # eBay's scraper drives a real headless browser (via `ferrum`) rather
  # than plain HTTP, so WebMock can't intercept it the way it does for
  # the plain-HTTP scrapers. Instead we stub out `fetch_rendered`
  # itself with canned HTML -- this still exercises every bit of real
  # logic (card parsing, filtering, spec matching) without needing a
  # real Chrome process or a real network call in the test suite.
  class EbayScraperTest < ActiveSupport::TestCase
    test "parses s-card listings and skips the 'Shop on eBay' placeholder and bid listings" do
      html = <<~HTML
        <ul>
          <li class="s-card">
            <div class="su-card-container__header"><a class="s-card__link" href="https://www.ebay.com/itm/9988776655">view</a></div>
            <div class="s-card__title">MacBook Pro 14 M5 Max 128GB 2TB</div>
            <div class="s-card__price">$4,299.00</div>
            <div class="s-card__subtitle">Used</div>
          </li>
          <li class="s-card">
            <div class="su-card-container__header"><a class="s-card__link" href="https://www.ebay.com/itm/1112223334">view</a></div>
            <div class="s-card__title">Shop on eBay</div>
          </li>
          <li class="s-card">
            <div class="su-card-container__header"><a class="s-card__link" href="https://www.ebay.com/itm/5556667778">view</a></div>
            <div class="s-card__title">MacBook Pro 14 M5 Max 128GB 2TB</div>
            <div class="s-card__price">$3,900.00</div>
            <div class="s-card__subtitle">3 bids</div>
          </li>
        </ul>
      HTML

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      scraper = EbayScraper.new(search)
      scraper.define_singleton_method(:fetch_rendered) { |*_args, **_kwargs| html }

      results = scraper.scrape

      assert_equal 1, results.length
      assert_equal "ebay", results.first[:source]
      assert_equal "9988776655", results.first[:listing_id]
      assert_equal 4299.00, results.first[:price_usd]
    end
  end
end
