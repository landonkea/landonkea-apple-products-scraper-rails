require "test_helper"

module Scrapers
  class PinkbikeScraperTest < ActiveSupport::TestCase
    test "accepts USD-priced listings and skips other currencies" do
      html = <<~HTML
        <div class="bsitem">
          <div class="bsitem-title"><a href="/buysell/1234567/">Lectric XPedition Folding E-Bike 48V 20Ah 750W</a></div>
          <td class="bsitem-price"><b>$1,100 USD</b></td>
          <div class="itemdetail">Condition : Excellent</div>
          <table class="bsitem-details"><tr><td>seller</td></tr><tr><td>Phoenix, AZ</td></tr></table>
        </div>
        <div class="bsitem">
          <div class="bsitem-title"><a href="/buysell/7654321/">Aventon Folding E-Bike</a></div>
          <td class="bsitem-price"><b>$1,400 CAD</b></td>
        </div>
      HTML

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "Folding step-through commuter e-bike" }
      scraper = PinkbikeScraper.new(search)
      # Pinkbike paginates (3 pages) -- only hand back real cards for
      # page 1, empty pages after that, so the assertions below aren't
      # counting the same two listings three times over.
      scraper.define_singleton_method(:fetch_rendered) do |url, **_kwargs|
        url.include?("page=1") ? html : "<html></html>"
      end

      results = scraper.scrape

      assert_equal 1, results.length
      assert_equal "pinkbike-1234567", results.first[:listing_id]
      assert_equal 1100.0, results.first[:price_usd]
      assert_equal "Excellent", results.first[:condition]
    end
  end
end
