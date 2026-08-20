module Scrapers
  # Gazelle's real storefront lives on buy.gazelle.com (a stock Shopify
  # site, not www.gazelle.com, which 404s on every real route), and
  # Shopify exposes its whole catalog as plain public JSON endpoints --
  # no HTML scraping, no JavaScript needed at all. A direct port of
  # Python's scrapers/gazelle.py. Note Gazelle genuinely does not stock
  # MacBooks (confirmed live in the Python version) -- 0 results for
  # that search is correct, not a bug.
  class GazelleScraper < BaseScraper
    def scrape
      if search[:model_keywords].present?
        search[:model_keywords].flat_map { |keyword| scrape_collection(keyword) }
      else
        scrape_suggest(search[:product_name])
      end
    end

    private

    # e.g. "iPhone 17 Pro Max" -> "iphone-17-pro-max", Gazelle's
    # collection-handle convention.
    def scrape_collection(keyword)
      handle = keyword.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      url = "https://buy.gazelle.com/collections/#{handle}/products.json?limit=250"
      body = fetch(url)
      data = JSON.parse(body)

      (data["products"] || []).flat_map { |product| parse_product_variants(product) }
    rescue => e
      Rails.logger.warn("[GazelleScraper] collection #{handle} failed: #{e.message}")
      []
    end

    def scrape_suggest(query)
      url = "https://buy.gazelle.com/search/suggest.json?q=#{CGI.escape(query)}&resources[type]=product"
      body = fetch(url)
      data = JSON.parse(body)

      products = data.dig("resources", "results", "products") || []
      products.filter_map { |product| parse_suggest_product(product) }
    rescue => e
      Rails.logger.warn("[GazelleScraper] suggest failed: #{e.message}")
      []
    end

    def parse_product_variants(product)
      title = product["title"]
      (product["variants"] || []).filter_map do |variant|
        next unless variant["available"]

        build_candidate(
          source: "gazelle",
          listing_id: "gazelle-#{variant['id']}",
          title: title,
          price_usd: variant["price"].to_f,
          url: "https://buy.gazelle.com/products/#{product['handle']}",
          condition: variant["option2"]
        )
      end
    end

    def parse_suggest_product(product)
      build_candidate(
        source: "gazelle",
        listing_id: "gazelle-#{product['id']}",
        title: product["title"],
        price_usd: product["price"].to_f,
        url: product["url"] ? "https://buy.gazelle.com#{product['url']}" : nil,
        condition: nil
      )
    end
  end
end
