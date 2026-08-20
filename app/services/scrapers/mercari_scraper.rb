module Scrapers
  # Mercari's search results are painted in by client-side JavaScript,
  # so this renders the page with a real (headless) browser rather than
  # fetching plain HTML. Uses Mercari JAPAN (jp.mercari.com), not the
  # US site -- the Python version found prices there running 10-30%
  # cheaper for the same used electronics. A direct port of Python's
  # scrapers/mercari.py, minus its "fetch the detail page to find a
  # missing chip name" fallback (see README) -- that extra per-listing
  # page fetch is a lot of additional browser time for a spec bonus
  # that's nice-to-have, not required for a listing to match at all.
  class MercariScraper < BaseScraper
    def scrape
      url = "https://jp.mercari.com/search?keyword=#{CGI.escape(search[:product_name])}"
      html = fetch_rendered(url, wait: 5)
      doc = parse_html(html)

      cards = doc.css("li[data-testid='item-cell']")
      cards.filter_map { |card| parse_card(card) }
    end

    private

    def parse_card(card)
      link = card.at_css("a[data-testid='thumbnail-link']") || card.at_css("a")
      href = link&.[]("href")
      title = card.at_css("span[data-testid='thumbnail-item-name']")&.text&.strip
      # Despite being the Japan-domain site, Mercari shows this price
      # already denominated in dollars (with a literal "$" prefix) once
      # rendered -- the Python version relied on the exact same thing,
      # stripping a "$" rather than converting from yen, so there's no
      # currency-conversion math needed here either.
      price_text = card.at_css("span.number__6b270ca7")&.text || card.text[/\$[\d,.]+/]
      return nil if href.blank? || title.blank? || price_text.blank?

      url = href.start_with?("http") ? href : "https://jp.mercari.com#{href}"
      listing_id = url[%r{/(?:item|shops/product)/([^/]+)/?}, 1] || url.split("/").last

      build_candidate(
        source: "mercari",
        listing_id: listing_id,
        title: title,
        price_usd: parse_price(price_text),
        url: url,
        # Mercari never exposes a structured condition on the search
        # results page -- matches Python, which leaves this nil too.
        condition: nil
      )
    end
  end
end
