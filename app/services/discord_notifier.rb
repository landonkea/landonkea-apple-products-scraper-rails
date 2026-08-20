# Posts alerts into a Discord channel via a webhook -- a webhook is
# just a special URL Discord gives you that accepts a JSON POST and
# turns it into a message, no bot login required. A port of Python's
# `Notifier` class, covering its three alert types: a new/great deal
# found, an already-known listing's price dropping, and a great deal
# that vanished suspiciously fast (probably bought by someone else).
class DiscordNotifier
  SUCCESS_STATUS = 204
  RATE_LIMITED_STATUS = 429

  # ── Which webhook a search's alerts go to ────────────────────────
  # Every search but the e-bike one shares the same webhook env vars.
  # Non-production environments (development, test, and a real
  # `staging` Rails environment, see config/environments/staging.rb)
  # never post to the real production channel -- they look for a
  # separate "_DEV" webhook instead, and simply skip posting (with a
  # log line) if that isn't set. This mirrors Python's is_production()
  # gate in notifier.py, which existed after a local test run once
  # nearly spammed the real Discord channel.
  def self.webhook_url(env_var_name)
    key = Rails.env.production? ? env_var_name : "#{env_var_name}_DEV"
    ENV.fetch(key, nil).presence
  end

  # `send_alert` builds and posts one embed summarizing the top deals
  # found for a single search (e.g. "MacBook Pro"). `search` is the
  # search hash from ScrapeRunner::SEARCHES, `top_deals` is an array of
  # already-scored Listing records (best first), and `stats` is the
  # price-range hash PriceAnalyzer computed for that same batch.
  def self.send_alert(search, top_deals, stats)
    return false if top_deals.empty?

    webhook_url = webhook_url(search[:discord_webhook_env])
    if webhook_url.blank?
      Rails.logger.info("[DiscordNotifier] no webhook configured, skipping alert for: #{search[:product_name]}")
      return false
    end

    best = top_deals.first
    color = best.is_great_deal? ? 0x00ff00 : 0xffaa00

    market_field = {
      name: "📊 Market Snapshot",
      value: "**#{stats[:count]}** listings found\n" \
             "Price range: **#{format_price(stats[:min])}** - **#{format_price(stats[:max])}**\n" \
             "Median: **#{format_price(stats[:median])}**",
      inline: false
    }

    listing_fields = top_deals.each_with_index.map { |listing, index| new_deal_field(listing, index + 1) }

    embed = {
      title: "🎯 #{search[:product_name]} Deal Alert",
      color: color,
      fields: [ market_field ] + listing_fields,
      footer: { text: search[:product_name] }
    }

    post_embed(webhook_url, embed)
  end

  # `send_price_drop_alert` fires for listings we've ALREADY seen
  # before whose price just dropped meaningfully (see
  # PriceAnalyzer.meaningful_drop?) -- a separate alert type from
  # send_alert above, which only ever looks at a listing the first time
  # it's found. `price_drops` is an array of [listing, old_price] pairs.
  def self.send_price_drop_alert(search, price_drops)
    return false if price_drops.empty?

    webhook_url = webhook_url(search[:discord_webhook_env])
    return false if webhook_url.blank?

    fields = price_drops.map { |listing, old_price| price_drop_field(listing, old_price) }

    embed = {
      title: "📉 #{search[:product_name]} Price Drop Alert",
      color: 0x3498db,
      fields: fields,
      footer: { text: search[:product_name] }
    }

    post_embed(webhook_url, embed)
  end

  # `send_scooped_deal_alert` fires when a listing that was flagged a
  # great deal disappears (not seen in a scrape again) within 24 hours
  # of first being found -- a strong signal someone else bought it
  # before we could. `scooped` is an array of Listing records already
  # marked is_active: false.
  def self.send_scooped_deal_alert(search, scooped)
    return false if scooped.empty?

    webhook_url = webhook_url(search[:discord_webhook_env])
    return false if webhook_url.blank?

    fields = scooped.map { |listing| scooped_deal_field(listing) }

    embed = {
      title: "🏃 Great Deal Alert, Scooped!",
      color: 0xe74c3c,
      fields: fields,
      footer: { text: "A great deal disappeared shortly after being found, probably sold to someone else." }
    }

    post_embed(webhook_url, embed)
  end

  def self.new_deal_field(listing, rank)
    emoji = listing.is_great_deal? ? "🔥" : "💰"
    age = listing_age(listing.first_seen_at)
    age_suffix = age.present? ? ", #{age}" : ""

    {
      name: "#{emoji} ##{rank}, #{format_price(listing.price_usd)} | #{listing.source}",
      value: "[#{listing.title.to_s.truncate(80)}](#{listing.url}), Score: #{listing.deal_score}/100#{age_suffix}",
      inline: false
    }
  end

  def self.price_drop_field(listing, old_price)
    drop_usd = old_price - listing.price_usd
    drop_percent = old_price.positive? ? (drop_usd / old_price) * 100 : 0

    {
      name: "📉 #{listing.source}, #{format_price(old_price)} → #{format_price(listing.price_usd)} (-#{drop_percent.round}%)",
      value: "[#{listing.title.to_s.truncate(80)}](#{listing.url}), saved #{format_price(drop_usd)}",
      inline: false
    }
  end

  def self.scooped_deal_field(listing)
    lifetime_hours = if listing.first_seen_at && listing.last_seen_at
      (listing.last_seen_at - listing.first_seen_at) / 3600.0
    else
      0.0
    end

    {
      name: "🏃 #{format_price(listing.price_usd)} | #{listing.source}, gone in #{lifetime_hours.round}h",
      value: "[#{listing.title.to_s.truncate(80)}](#{listing.url}), was a great deal",
      inline: false
    }
  end

  # Renders a dollar amount the way every embed here shows one --
  # whole dollars, comma-separated, e.g. "$5,000".
  def self.format_price(amount)
    "$#{ActiveSupport::NumberHelper.number_to_delimited(amount.round)}"
  end

  # Renders how long ago a listing first appeared, e.g. "Listed 4h
  # ago" -- matches Python's format_listing_age.
  def self.listing_age(first_seen_at)
    return "" unless first_seen_at

    seconds = [ Time.current - first_seen_at, 0 ].max
    hours = seconds / 3600.0
    days = hours / 24.0

    if hours < 1
      "Listed #{[ (seconds / 60).to_i, 1 ].max}m ago"
    elsif days < 1
      "Listed #{hours.to_i}h ago"
    else
      "Listed #{days.to_i}d ago"
    end
  end

  # The actual HTTP call, with a single retry on Discord's 429 rate
  # limit -- Discord's response body tells us exactly how long to wait.
  def self.post_embed(webhook_url, embed)
    response = post_once(webhook_url, embed)

    if response.status == SUCCESS_STATUS
      true
    elsif response.status == RATE_LIMITED_STATUS
      retry_after = begin
        JSON.parse(response.body)["retry_after"] || 2
      rescue JSON::ParserError
        2
      end
      sleep(retry_after + 0.5)
      post_once(webhook_url, embed).status == SUCCESS_STATUS
    else
      Rails.logger.warn("[DiscordNotifier] unexpected status #{response.status}")
      false
    end
  rescue Faraday::Error => e
    # A network hiccup shouldn't crash the whole scrape run.
    Rails.logger.warn("[DiscordNotifier] request failed: #{e.message}")
    false
  end

  def self.post_once(webhook_url, embed)
    Faraday.post("#{webhook_url}?wait=true") do |req|
      req.headers["Content-Type"] = "application/json"
      req.options.timeout = 15
      req.body = { username: "Apple Product Scraper", embeds: [ embed ] }.to_json
    end
  end
end
