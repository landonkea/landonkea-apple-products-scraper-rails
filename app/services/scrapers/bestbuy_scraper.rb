module Scrapers
  # Best Buy's search results are client-side rendered, so this needs a
  # real browser fetch. There's no dedicated "Open Box" search URL, so
  # the query itself is prefixed "open box" and every card is then
  # double-checked for an actual Open Box badge -- items that look like
  # regular new/sealed stock are skipped, matching the original
  # intent (open-box/clearance deals only). A direct port of Python's
  # scrapers/bestbuy.py.
  class BestbuyScraper < BaseScraper
    def scrape
      url = "https://www.bestbuy.com/site/searchpage.jsp?st=#{CGI.escape("open box #{search[:product_name]}")}&sort=PRICE_LOW_TO_HIGH"
      html = fetch_rendered(url, wait: 5)
      doc = parse_html(html)

      doc.css("li.product-list-item, .product-list-item").filter_map { |card| parse_card(card) }
    end

    private

    def parse_card(card)
      title = card.at_css("h3.product-title")&.text&.strip
      link = card.at_css("a.product-list-item-link") || card.at_css("a")
      href = link&.[]("href")
      return nil if title.blank? || href.blank?

      condition = detect_condition(card, href)
      return nil unless condition # only genuine Open Box items count here

      price_text = card.at_css("[data-testid='price-block-customer-price'] .font-500")&.text || card.at_css(".priceView-customer-price span")&.text
      return nil if price_text.blank?

      url = href.start_with?("http") ? href : "https://www.bestbuy.com#{href}"
      listing_id = card["data-product-id"] || url[%r{/sku/(\d+)}, 1] || url.split("/").last

      build_candidate(
        source: "bestbuy",
        listing_id: listing_id,
        title: title,
        price_usd: parse_price(price_text),
        url: url,
        condition: condition
      )
    end

    def detect_condition(card, href)
      return "Open Box" if href.include?("/openbox")

      badge = card.at_css("[data-testid='price-block-badging-text']")&.text ||
        card.at_css("[data-testid*='open-box-sku-messaging']")&.text ||
        card.text
      badge.to_s.downcase.include?("open box") ? "Open Box" : nil
    end
  end
end
