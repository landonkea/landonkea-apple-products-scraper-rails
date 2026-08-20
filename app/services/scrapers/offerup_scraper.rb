module Scrapers
  # OfferUp's search page ships its results as a big JSON blob in a
  # `<script id="__NEXT_DATA__">` tag (a standard Next.js pattern) that
  # only appears after the page's JavaScript runs, so this fetches with
  # a real browser and reads that script tag straight out of the
  # rendered DOM. Falls back to scanning rendered listing cards
  # directly if the JSON blob isn't there or doesn't parse. A
  # simplified port of Python's scrapers/offerup.py -- the Python
  # version tries four different extraction strategies in a fallback
  # chain (JSON blob, JSON-LD tags, rendered DOM, raw link scan); this
  # keeps the two that matter most and skips the two narrower
  # last-resort strategies, see README.
  class OfferupScraper < BaseScraper
    def scrape
      html = fetch_rendered("https://offerup.com/search/?q=#{CGI.escape(search[:product_name])}", wait: 6)
      doc = parse_html(html)

      from_next_data(doc) || from_rendered_dom(doc) || []
    end

    private

    def from_next_data(doc)
      script = doc.at_css("script#__NEXT_DATA__")
      return nil unless script

      data = JSON.parse(script.text)
      tiles = data.dig("props", "pageProps", "searchFeedResponse", "looseTiles") || []
      tiles = tiles.select { |tile| tile["__typename"] == "ModularFeedTileListing" }
      return nil if tiles.empty?

      tiles.filter_map { |tile| parse_tile(tile) }
    rescue JSON::ParserError
      nil
    end

    def parse_tile(tile)
      listing = tile["listing"] || tile
      title = listing["title"]
      listing_id = listing["listingId"] || listing["id"]
      price = listing.dig("price", "value") || listing["price"]
      return nil if title.blank? || listing_id.blank? || price.blank?

      build_candidate(
        source: "offerup",
        listing_id: listing_id.to_s,
        title: title,
        price_usd: price.to_f,
        url: "https://offerup.com/item/detail/#{listing_id}",
        condition: listing["condition"],
        location: listing["location"]
      )
    end

    def from_rendered_dom(doc)
      # Try the higher-level card wrapper first; only fall back to a
      # bare link scan if no wrapper elements were found at all --
      # combining both into one selector would match a card AND the
      # link inside it as two separate "cards" for the same listing.
      cards = doc.css("[data-testid='search-card'], article")
      cards = doc.css("a[href*='/item/detail/']") if cards.empty?
      return nil if cards.empty?

      cards.filter_map { |card| parse_card(card) }
    end

    def parse_card(card)
      link = card.name == "a" ? card : card.at_css("a[href*='/item/detail/']")
      href = link&.[]("href")
      return nil if href.blank?

      title = card.at_css("[class*='title']")&.text&.strip || card.text.to_s.strip.first(100)
      price_text = card.at_css("[class*='price']")&.text
      return nil if title.blank? || price_text.blank?

      listing_id = href[%r{/item/detail/([^/?]+)}, 1]
      return nil if listing_id.blank?

      build_candidate(
        source: "offerup",
        listing_id: listing_id,
        title: title,
        price_usd: parse_price(price_text),
        url: href.start_with?("http") ? href : "https://offerup.com#{href}",
        condition: nil
      )
    end
  end
end
