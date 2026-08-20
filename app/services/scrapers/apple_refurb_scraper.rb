module Scrapers
  # Apple's refurb store embeds its entire product grid as JSON right
  # inside a <script> tag (`window.REFURB_GRID_BOOTSTRAP = {...}`), so
  # this never needs to touch a single CSS selector or render any
  # JavaScript -- just fetch the page and parse the embedded JSON. A
  # direct port of Python's scrapers/apple_refurb.py.
  class AppleRefurbScraper < BaseScraper
    PAGES = {
      "MacBook Pro" => [
        "https://www.apple.com/shop/refurbished/mac/14-inch-macbook-pro",
        "https://www.apple.com/shop/refurbished/mac/16-inch-macbook-pro"
      ],
      "iPhone Pro Max" => [ "https://www.apple.com/shop/refurbished/iphone" ],
      "iPad Pro" => [ "https://www.apple.com/shop/refurbished/ipad/ipad-pro" ]
    }.freeze

    def scrape
      urls = PAGES[search[:product_name]] || []
      seen_ids = Set.new

      urls.flat_map { |url| scrape_page(url, seen_ids) }
    end

    private

    def scrape_page(url, seen_ids)
      html = fetch(url)
      match = html.match(/window\.REFURB_GRID_BOOTSTRAP\s*=\s*(\{.*?\});/m)
      return [] unless match

      data = JSON.parse(match[1])
      tiles = data["tiles"] || []

      tiles.filter_map { |tile| parse_tile(tile, seen_ids) }
    rescue JSON::ParserError => e
      Rails.logger.warn("[AppleRefurbScraper] could not parse embedded JSON: #{e.message}")
      []
    end

    def parse_tile(tile, seen_ids)
      title = tile["title"]
      return nil if title.blank?

      product_path = tile["productDetailsUrl"]
      return nil if product_path.blank?
      return nil if seen_ids.include?(product_path)
      seen_ids << product_path

      price = tile.dig("price", "currentPrice", "raw_amount")
      return nil if price.blank?

      build_candidate(
        source: "apple_refurb",
        listing_id: product_path,
        title: title,
        price_usd: price.to_f,
        url: "https://www.apple.com#{product_path}",
        condition: "Refurbished",
        location: "Apple Refurbished Store"
      )
    end
  end
end
