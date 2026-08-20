# Apple Products Scraper (Rails)

This app checks ten different marketplaces every day for used and refurbished
Apple hardware, and one more for a specific kind of e-bike, and tells you
about the good deals on Discord. It's a Ruby on Rails rewrite of a
[Python project](https://github.com/landonkea/landonkea-apple-products-scraper)
that did the same job, rebuilt from scratch so it runs as a normal Rails app
instead of a scheduled GitHub Actions script.

You don't need to know how to code to use this. This document explains what
every piece does in plain language.

## What it actually does

Once a day, this app visits eBay, Swappa, Apple's own refurbished store, Back
Market, Mercari, Best Buy, OfferUp, Newegg, Gazelle, and Craigslist looking
for four things: a MacBook Pro, an iPhone Pro Max, an iPad Pro, and (on a
different set of sites) a folding step-through e-bike. For each one it finds,
it:

1. Reads the listing's title to figure out the specs (how much RAM, how much
   storage, which chip, and so on for a computer or phone; wheel size,
   battery size, motor power for a bike).
2. Throws out anything that isn't really the product, like a phone case that
   happens to mention "iPhone 17 Pro Max" in its own title.
3. Gives it a score from 0 to 100 based on how its price compares to
   everything else found that day, plus a handful of smaller bonuses (a
   trustworthy marketplace, new condition, the RAM tier you actually want).
4. Saves it to a database, and remembers every price it's ever seen that
   listing at.
5. If it's a genuinely great price, or a listing you've seen before just got
   cheaper, or a great deal vanished suspiciously fast (probably because
   someone else bought it), posts about it in a Discord channel.

Then it shows you all of that on a simple web dashboard.

## The pieces, and how they fit together

**Where the data lives** (`app/models/`)
- `Listing` -- one row per product found on one marketplace. Holds the
  title, price, specs, its calculated deal score, and whether it's still
  for sale. `db/migrate/*_create_listings.rb` is the exact list of every
  field it stores.
- `PriceHistory` -- one row every time a listing's price is first recorded
  or changes. This is what draws the price-history chart on a listing's own
  page. A listing whose price never moves doesn't pile up duplicate rows --
  a new one is only written when the price is actually different from the
  last one recorded.

**Where the "what am I searching for" settings live**
  (`app/services/scrape_runner.rb`)
- The `SEARCHES` list at the top of this file is the whole
  "what to search for" configuration: which chip generations count as
  MacBook Pro's "current" line-up, what RAM tier is preferred, what counts
  as an e-bike we'd actually want. When Apple ships a new chip next year,
  this is the one place you'd edit.
- `SITES` says which of the ten marketplaces applies to which kind of
  search (Apple's own refurb store, for example, never carries e-bikes, so
  it's skipped for that search instead of wasting a request).

**Reading a title and figuring out what it means**
  (`app/services/spec_parser.rb`)
- Every marketplace hands back plain-English titles, not clean structured
  data. This file is a big collection of regular expressions that pull the
  real specs back out -- "128GB" near the word "RAM" means 128GB of memory,
  "2TB" always means storage, "M5 Max" is a chip name, and so on.

**Deciding whether a listing belongs in our results**
  (`app/services/scrapers/listing_filter.rb`)
- After a title is parsed, this checks whether the listing is really the
  product we want (not an accessory), matches what we asked for (the right
  chip, the right storage range), and is priced in a sane range. Every
  scraper runs its findings through this exact same check.

**Actually visiting each marketplace** (`app/services/scrapers/`)
- One file per marketplace, all inheriting from `base_scraper.rb`. Six of
  them (eBay, Swappa, Apple Refurb, Newegg, Gazelle, Craigslist) just fetch
  a normal web page -- their listings are already in the plain HTML. Five of
  them (eBay again as a fallback, Back Market, Mercari, Best Buy, OfferUp,
  and Pinkbike for the e-bike search) need a real, invisible Chrome browser
  running in the background (the `ferrum` gem drives one) because their
  listings only appear after the page's own JavaScript finishes running.

**Turning listings into scores** (`app/services/price_analyzer.rb`)
- Compares every listing found in one run against the median price of that
  same batch. Below the median scores higher, above it scores lower. Adds
  smaller bonuses for condition, marketplace trustworthiness, and
  product-specific things (RAM tier, chip generation, or, for e-bikes,
  weight capacity and battery size). Also catches listings priced
  suspiciously low while claiming to be brand new -- that's usually a typo
  or a scam, not a real deal, so those get flagged and capped instead of
  shown off as the best find of the day.

**Sending Discord alerts** (`app/services/discord_notifier.rb`)
- Posts three different kinds of message: a new great deal was found, an
  already-known listing's price just dropped, or a great deal disappeared
  within 24 hours of being found (a strong sign someone else bought it
  first). The e-bike search posts to its own separate Discord channel so
  it doesn't get lost among MacBook and iPhone alerts.

**Running all of this automatically** (`app/jobs/scrape_listings_job.rb`
  and `config/recurring.yml`)
- Rails 8 ships with a built-in job scheduler called Solid Queue.
  `config/recurring.yml` tells it to run the scrape job once a day at 13:00
  UTC (6am Arizona time), the same schedule the original Python version
  used. You never have to remember to run this by hand.

**The dashboard** (`app/controllers/listings_controller.rb` and
  `app/views/listings/`)
- The main page lists every currently-active listing, best score first,
  with dropdowns to filter by product or marketplace and a checkbox for
  "great deals only." Clicking into a listing shows its full price history
  as a simple bar chart, plus a link straight to the real listing.

## Running it yourself

```
bin/setup      # installs gems, sets up the database
bin/dev        # starts the web server at http://localhost:3000
```

To trigger a scrape by hand instead of waiting for the daily schedule:

```
bin/rails runner "ScrapeRunner.call"
```

To run the test suite:

```
bin/rails test
```

## Environment variables, and why each one exists

Copy `.env.example` to `.env` and fill in whichever of these you actually
want to use -- every one of them is optional, and the app runs fine with
none of them set, it just won't post to Discord.

| Variable | What it's for |
|---|---|
| `DISCORD_WEBHOOK_URL` | Where MacBook/iPhone/iPad deal alerts get posted, in production. |
| `DISCORD_WEBHOOK_URL_DEV` | Same, but used instead whenever you're NOT running in the `production` Rails environment, so a local test run can never accidentally post to your real channel. |
| `DISCORD_WEBHOOK_URL_EBIKE` | A separate channel just for e-bike alerts, production. |
| `DISCORD_WEBHOOK_URL_EBIKE_DEV` | Non-production counterpart to the one above. |
| `CRAIGSLIST_REGIONS` | Comma-separated Craigslist metro slugs to search, e.g. `phoenix,tucson`. Defaults to just Phoenix. |
| `BROWSER_PATH` | Full path to a Chrome/Chromium binary, only needed if Ferrum can't find one automatically. The Docker image sets this for you. |

## The three environments

The original Python project distinguished dev, staging, and production runs
with a single `ENVIRONMENT` variable, mainly so a local test run could never
lock the real production database file or spam the real Discord channel.
Rails already solves almost this entire problem on its own, so this rewrite
leans on that instead of reinventing it:

- **development** -- your own machine, `storage/development.sqlite3`, and
  (per the table above) alerts go to the `_DEV` Discord webhook, if you've
  set one.
- **staging** (`config/environments/staging.rb`, a real Rails environment
  added specifically for this) -- production-like settings, but its own
  separate `storage/staging.sqlite3` database (see `config/database.yml`)
  and its own `_DEV` Discord webhooks. This is what you'd deploy somewhere
  and run for real before trusting it with the actual production channel.
- **production** -- the real deployed app, real database, real Discord
  channel.

Because `config/database.yml` gives every one of these its own database
file automatically, there's no way for a staging or development run to
collide with production data the way the original Python project's shared
SQLite file once did.

## How the price-history and drop-alert feature works

Every time a listing is scraped, its price is compared against the last
price recorded for it in `price_histories`. Three different things can
happen:

1. **It's a brand-new listing.** No history to compare against, so this is
   just its first data point.
2. **The price is unchanged.** Nothing new gets written -- the history table
   only grows when something actually changed, not on every single scrape.
3. **The price dropped by at least 5% AND at least $50** (both conditions,
   not just one -- a 5% drop on a $60 item is only $3, not worth an alert,
   and a $50 drop on an $8,000 item is less than 1%, also not worth one).
   This triggers a separate "price drop" Discord alert, distinct from the
   "new great deal found" alert.

Separately, if a listing was ever flagged a great deal and then stops
showing up in scrapes within 24 hours of first being found, that's treated
as a strong signal someone else bought it -- it gets its own "scooped"
alert so you know your scoring is finding things worth having.

## What's different from the Python version, and why

- **No `generation_family` auto-expanding config macro.** The Python
  version let you write `generation_family: mac_chip, current_gen: 5,
  lookback: 3` and have it expand into "search M5 Max, M4 Max, and M3 Max"
  automatically. This rewrite just lists `chip_options: ["M5 Max", "M4
  Max", "M3 Max"]` directly in `ScrapeRunner::SEARCHES`. Bumping to the
  next chip generation next year is a one-line edit either way -- the
  macro layer added complexity without changing what actually happens, so
  it was left out.
- **Vision Pro and the apparel example search were left out.** The Python
  config had a live Vision Pro search and a commented-out "boots" example
  showing the product-type system could handle a totally different
  category. This rewrite focuses on the four searches described in the
  build brief (MacBook Pro, iPhone Pro Max, iPad Pro, e-bike) rather than
  also porting a category that wasn't part of the ask.
- **No watchlist feature.** The Python version let you manually paste a
  specific listing URL into a JSON file to track it regardless of whether
  it scored as a deal. Out of scope for this rewrite -- the four automatic
  searches above cover the actual ask.
- **No Facebook Marketplace scraper.** The Python version's own Facebook
  scraper was a stub, too -- it requires a logged-in session cookie with no
  real login flow implemented, and stays disabled by default. Not carried
  forward here since it never did anything in the original either.
- **OfferUp uses two extraction strategies, not four.** The Python version
  tried a JSON blob, then JSON-LD tags, then a rendered-DOM scan, then a
  raw link scan, in that order, as a fallback chain. This rewrite keeps the
  two that matter most (the JSON blob, then a rendered-DOM scan) and skips
  the two narrower last-resort strategies.
- **Mercari's "fetch the detail page when the chip is missing" fallback was
  dropped.** The Python version would load an entire second page per
  listing just to try to find a chip name buried in the description. That's
  a lot of extra headless-browser time for what's only ever a small scoring
  bonus, not something a listing needs to match at all.
- **No GitHub Pages price-trend export.** The Python version published a
  separate static site with historical trend charts. This app's own
  dashboard already shows a listing's price history directly, so a second,
  separate publishing pipeline wasn't rebuilt.

## Known limitations

- **Back Market is the least reliable scraper here.** It sits behind
  Cloudflare bot detection strong enough that the original Python version
  needed a stealth browser plugin to get through reliably. Ruby's `ferrum`
  gem has no equivalent, so this scraper does its best with a plain
  headless browser but can't guarantee getting past Cloudflare on every
  single run.
- **None of the scrapers have been run against the real, live marketplace
  sites** (only against saved sample HTML in the test suite) -- marketplace
  page layouts change over time, and a selector that's correct today may
  need a small update down the road if a site redesigns its search page.
