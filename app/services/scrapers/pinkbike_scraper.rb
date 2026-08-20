module Scrapers
  # Pinkbike's BuySell marketplace returns a plain HTTP 403 from
  # Cloudflare on a bare curl-style request, but (unlike BackMarket)
  # a vanilla headless Chrome is enough to get through -- no stealth
  # plugin needed. Category 63 is "Ebikes - Urban/Commuter" (the
  # category this app's e-bike search cares about); region 3 covers
  # US/Canada listings. Only used for the e-bike search -- see
  # ScrapeRunner::SITES' applicable_product_types for this scraper. A
  # direct port of Python's scrapers/pinkbike.py.
  class PinkbikeScraper < BaseScraper
    CATEGORY = 63
    REGION = 3
    MAX_PAGES = 3

    def scrape
      (1..MAX_PAGES).flat_map { |page| scrape_page(page) }
    end

    private

    def scrape_page(page)
      url = "https://www.pinkbike.com/buysell/list/?category=#{CATEGORY}&region=#{REGION}&sort=price-up&page=#{page}"
      html = fetch_rendered(url, wait: 5)
      doc = parse_html(html)

      doc.css("div.bsitem").filter_map { |card| parse_card(card) }
    rescue => e
      Rails.logger.warn("[PinkbikeScraper] page #{page} failed: #{e.message}")
      []
    end

    def parse_card(card)
      link = card.at_css("div.bsitem-title a")
      title = link&.text&.strip
      href = link&.[]("href")
      return nil if title.blank? || href.blank?

      price_text = card.at_css("td.bsitem-price b")&.text
      return nil if price_text.blank?
      # Only accept prices explicitly stated in USD -- Pinkbike mixes
      # CAD/EUR/GBP listings into the same result set, and we don't
      # attempt any currency conversion.
      return nil unless price_text.include?("$") && !price_text.match?(/CAD|CDN/i)

      condition = extract_detail(card, "Condition")
      location = card.at_css("table.bsitem-details tr:nth-child(2)")&.text&.strip

      url = href.start_with?("http") ? href : "https://www.pinkbike.com#{href}"
      listing_id = "pinkbike-#{url[%r{/buysell/(\d+)/}, 1]}"

      build_candidate(
        source: "pinkbike",
        listing_id: listing_id,
        title: title,
        price_usd: parse_price(price_text),
        url: url,
        condition: condition,
        location: location
      )
    end

    def extract_detail(card, label)
      row = card.at_css("div.itemdetail")&.text
      return nil unless row

      match = row.match(/#{Regexp.escape(label)}\s*:\s*([^\n]+)/i)
      match && match[1].strip
    end
  end
end
