require "test_helper"

module Scrapers
  class MercariScraperTest < ActiveSupport::TestCase
    test "parses rendered item cells" do
      html = <<~HTML
        <li data-testid="item-cell">
          <a data-testid="thumbnail-link" href="/item/m12345678901/">
            <span data-testid="thumbnail-item-name">MacBook Pro 14 M5 Max 128GB 2TB</span>
          </a>
          <span class="number__6b270ca7">$3,800.00</span>
        </li>
      HTML

      search = ScrapeRunner::SEARCHES.find { |s| s[:product_name] == "MacBook Pro" }
      scraper = MercariScraper.new(search)
      scraper.define_singleton_method(:fetch_rendered) { |*_args, **_kwargs| html }

      results = scraper.scrape

      assert_equal 1, results.length
      assert_equal "mercari", results.first[:source]
      assert_equal "m12345678901", results.first[:listing_id]
      assert_nil results.first[:condition]
    end
  end
end
