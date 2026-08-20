module Scrapers
  # Newegg's marketplace search is fully server-rendered, no headless
  # browser needed. Deliberately uses a bare product-name query with NO
  # sort parameter (default relevance) -- live testing in the Python
  # version found that appending chip/generation terms (the fix that
  # helps eBay) or sorting price-ascending both backfire here, surfacing
  # accessories/cases instead of real listings. Relevance filtering is
  # left entirely to SpecParser/ListingFilter instead. A direct port of
  # Python's scrapers/newegg.py.
  class NeweggScraper < BaseScraper
    MAX_PAGES = 5

    def scrape
      (1..MAX_PAGES).flat_map { |page| scrape_page(page) }
    end

    private

    def scrape_page(page)
      url = "https://www.newegg.com/p/pl?d=#{CGI.escape(search[:product_name])}&page=#{page}"
      html = fetch(url)
      doc = parse_html(html)
      cards = doc.css(".item-cell")
      return [] if cards.empty?

      cards.filter_map { |card| parse_card(card) }
    rescue => e
      Rails.logger.warn("[NeweggScraper] page #{page} failed: #{e.message}")
      []
    end

    def parse_card(card)
      link = card.at_css("a.item-title")
      title = link&.text&.strip
      href = link&.[]("href")
      return nil if title.blank? || href.blank?

      dollars = card.at_css("li.price-current strong")&.text
      cents = card.at_css("li.price-current sup")&.text
      return nil if dollars.blank?
      price = "#{dollars}#{cents}".delete(",").to_f

      condition = card.at_css("span.item-open-box-italic")&.text&.strip || "New"
      listing_id = href[%r{/p/([^/?]+)}, 1] || href

      build_candidate(
        source: "newegg",
        listing_id: listing_id,
        title: title,
        price_usd: price,
        url: href,
        condition: condition
      )
    end
  end
end
