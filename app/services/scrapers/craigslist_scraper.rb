module Scrapers
  # Craigslist ships a fully-populated `<ol class="cl-static-search-results">`
  # in the plain HTML response (a no-JS fallback list that's actually
  # complete, not a decoy), so this needs nothing fancier than a plain
  # HTTP fetch -- no headless browser required. A direct port of
  # Python's scrapers/craigslist.py.
  #
  # Craigslist is organized by metro region, not by state, so
  # REGIONS below is a list we loop over (one polite request per
  # region), aggregating results -- cross-region duplicates are
  # harmless, they're deduped downstream by (source, listing_id).
  class CraigslistScraper < BaseScraper
    # A starter region -- add more via the CRAIGSLIST_REGIONS env var
    # (comma-separated slugs) so a real deployment can cover its own
    # metro areas without a code change. See .env.example.
    DEFAULT_REGIONS = [ "phoenix" ].freeze

    def scrape
      regions.flat_map { |region| scrape_region(region) }
    end

    private

    def regions
      configured = ENV["CRAIGSLIST_REGIONS"]
      return configured.split(",").map(&:strip) if configured.present?

      DEFAULT_REGIONS
    end

    def scrape_region(region)
      url = "https://www.craigslist.org/search/area/#{region}?cat=sss&query=#{CGI.escape(query)}"
      html = fetch(url)
      doc = parse_html(html)

      doc.css("li.cl-static-search-result").filter_map do |card|
        parse_card(card, region)
      end
    rescue => e
      Rails.logger.warn("[CraigslistScraper] #{region} failed: #{e.message}")
      []
    end

    def parse_card(card, region)
      title = card.at_css("div.title")&.text&.strip
      price_text = card.at_css("div.price")&.text
      href = card["href"] || card.at_css("a")&.[]("href")
      location = card.at_css("div.location")&.text&.strip

      return nil if title.blank? || href.blank?

      listing_id = "craigslist-#{href.split('/').last.to_s.gsub(/\D/, '')}"

      build_candidate(
        source: "craigslist",
        listing_id: listing_id,
        title: title,
        price_usd: parse_price(price_text),
        url: href,
        condition: nil, # Craigslist has no structured condition field at all
        location: location.presence || region
      )
    end

    def query
      search[:product_name]
    end
  end
end
