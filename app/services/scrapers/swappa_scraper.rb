module Scrapers
  # Swappa is lenient enough that a plain HTTP fetch works fine (no
  # headless browser needed). It's a two-step process: first fetch a
  # category listing page to discover which specific product slugs
  # exist (e.g. one slug per MacBook Pro chip/RAM/storage combo), then
  # fetch each slug's own listings page for the actual for-sale cards.
  # A direct port of Python's scrapers/swappa.py.
  class SwappaScraper < BaseScraper
    CATEGORY_URLS = {
      "MacBook Pro" => "https://swappa.com/buy/macbooks/macbook-pro?sort=price_asc",
      "iPhone Pro Max" => "https://swappa.com/buy/iphones?sort=price_asc",
      "iPad Pro" => "https://swappa.com/buy/ipads/ipad-pro?sort=price_asc"
    }.freeze

    def scrape
      category_url = CATEGORY_URLS[search[:product_name]]
      return [] unless category_url

      slugs = discover_slugs(category_url)
      slugs.flat_map { |slug| scrape_slug(slug) }
    end

    private

    def discover_slugs(category_url)
      doc = parse_html(fetch(category_url))

      doc.css("div.card.card_product").filter_map do |card|
        title = card.at_css(".card-title.title")&.text&.strip
        next if title.blank?
        next if search[:screen_sizes].present? && search[:screen_sizes].none? { |size| title.include?(size.to_s) }

        slug = card.at_css("meta[itemprop='sku']")&.[]("content") || card.at_css("a")&.[]("href")&.split("/")&.last
        slug
      end.uniq
    end

    def scrape_slug(slug)
      doc = parse_html(fetch("https://swappa.com/listings/#{slug}"))

      doc.css("div.card.xui_card.xui_card_listing").filter_map { |card| parse_card(card) }
    rescue => e
      Rails.logger.warn("[SwappaScraper] slug #{slug} failed: #{e.message}")
      []
    end

    def parse_card(card)
      title = card.at_css("img")&.[]("alt") || card.at_css("div.headline")&.text&.strip
      price_node = card.at_css("div.price span[itemprop='price']")
      link = card.at_css("div.price a")
      return nil if title.blank? || price_node.blank? || link.blank?

      href = link["href"]
      listing_id = card.at_css("span.code.ms-2")&.text&.strip || href.to_s.split("/").last
      location = card.at_css("div.ships_from")&.text&.strip

      attrs = card.css("div.attrs span.attr").map { |node| node.text.strip }
      condition = attrs[0]

      build_candidate(
        source: "swappa",
        listing_id: listing_id,
        title: title,
        price_usd: parse_price(price_node.text),
        url: href,
        condition: condition,
        location: location
      )
    end
  end
end
