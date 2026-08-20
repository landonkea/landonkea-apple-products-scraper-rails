module Scrapers
  # eBay's "Buy It Now" search results are rendered client-side behind
  # bot detection strong enough that a plain HTTP fetch usually gets a
  # 403 -- this needs a real (headless) Chrome via `ferrum`. A direct
  # port of Python's scrapers/ebay.py, including its OR-group query
  # trick: without listing every chip/generation we care about in the
  # query itself, eBay's price-ascending sort surfaces a page of
  # accessories before a single real listing shows up.
  class EbayScraper < BaseScraper
    def scrape
      html = fetch_rendered(search_url, wait: 4)
      doc = parse_html(html)

      cards = doc.css("li.s-card, div.s-card, [class*='s-card']")
      cards = doc.css("li.s-item, .s-item__wrapper") if cards.empty?

      cards.filter_map { |card| parse_card(card) }
    end

    private

    def search_url
      terms = [ search[:product_name] ]
      terms += Array(search[:chip_options]) if search[:chip_options].present?
      terms += Array(search[:model_keywords]) if search[:model_keywords].present?
      query = terms.uniq.join(" OR ")

      "https://www.ebay.com/sch/i.html?_nkw=#{CGI.escape(query)}&LH_ItemCondition=4|3|2|1500|1000|2000&_sop=15&_ipg=120"
    end

    def parse_card(card)
      title = (card.at_css(".s-card__title") || card.at_css(".s-item__title"))&.text&.strip
      return nil if title.blank? || title.casecmp("shop on ebay").zero?

      link = card.at_css(".su-card-container__header a.s-card__link") || card.at_css("a.s-item__link")
      href = link&.[]("href")
      return nil if href.blank?

      price_text = (card.at_css(".s-card__price") || card.at_css(".s-item__price"))&.text
      condition = (card.at_css(".s-card__subtitle") || card.at_css(".s-item__subtitle"))&.text&.strip

      # Auctions ("3 bids", etc.) aren't a fixed Buy It Now price -- skip.
      return nil if title.downcase.include?("bid") || condition.to_s.downcase.include?("bid")

      listing_id = href[%r{/itm/(\d+)}, 1] || href[%r{/p/(\d+)}, 1] || Digest::MD5.hexdigest(href)

      build_candidate(
        source: "ebay",
        listing_id: listing_id,
        title: title,
        price_usd: parse_price(price_text),
        url: href.split("?").first,
        condition: condition
      )
    end
  end
end
