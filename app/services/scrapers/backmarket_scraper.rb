module Scrapers
  # BackMarket sits behind Cloudflare bot detection strong enough that
  # even a plain headless-Chrome fetch often gets blocked -- the Python
  # version needed a stealth plugin on top of Playwright to get through
  # reliably. `ferrum` has no equivalent stealth mode, so this scraper
  # is honest about being the weakest link: it renders the search page
  # with a real browser and reads whatever product cards actually made
  # it into the DOM, but can't guarantee getting past Cloudflare on
  # every run the way the Python version's stealth-patched browser
  # could. See README's "Known limitations" section.
  class BackmarketScraper < BaseScraper
    def scrape
      url = "https://www.backmarket.com/search?q=#{CGI.escape(search[:product_name])}"
      html = fetch_rendered(url, wait: 6)
      doc = parse_html(html)

      doc.css("article[data-spec='product-card-content'], article").filter_map { |card| parse_card(card) }
    end

    private

    def parse_card(card)
      link = card.at_css("a")
      href = link&.[]("href")
      # The link text alone (not the whole card's text, which would
      # also swallow the price and any badge text sitting next to it).
      title = link&.text&.strip.presence
      return nil if href.blank? || title.blank?

      price_text = card.at_css("[data-test='price'], .text-static-default-hi")&.text
      return nil if price_text.blank?

      url = href.start_with?("http") ? href : "https://www.backmarket.com#{href}"
      listing_id = url.split("/").last

      build_candidate(
        source: "backmarket",
        listing_id: listing_id,
        title: title.truncate(200),
        price_usd: parse_price(price_text),
        url: url,
        condition: nil
      )
    end
  end
end
