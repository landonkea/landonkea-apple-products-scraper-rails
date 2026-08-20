# Every marketplace hands scrapers the same raw material: a free-text
# title like 'Apple MacBook Pro 14" M5 Max Chip 128GB Memory 2TB SSD -
# Space Black' or "Lectric XPedition 20x4 Fat Tire Folding E-Bike 48V
# 20Ah". None of the sites expose the specs we actually care about as
# clean structured fields, so this class pulls them back out of the
# title text with regular expressions. A straight port of Python's
# product_types/electronics.py and product_types/ebike.py, merged into
# one file here since neither half is useful on its own outside this app.
class SpecParser
  # ── Electronics (MacBook Pro / iPhone Pro Max / iPad Pro) ───────────

  # Words that mean "this is an accessory/part, not the real computer"
  # -- a case, a charger, a replacement screen. A listing whose title or
  # marketplace condition label mentions one of these gets rejected
  # before any spec parsing even matters. A direct port of
  # electronics.py's ACCESSORY_KEYWORDS.
  MACBOOK_ACCESSORY_KEYWORDS = [
    "case", "cover", "skin", "decals", "sticker", "sleeve", "bag",
    "charger", "adapter", "power cord", "cable", "hub", "docking",
    "keyboard", "mouse", "trackpad", "screen protector", "tempered glass",
    "stand", "mount", "arm", "holder", "tray", "shell", "hard shell",
    "battery", "replacement battery", "strap", "backpack",
    "logic board", "motherboard", "lcd", "display", "digitizer",
    "flex cable", "ribbon cable", "hinge", "palm rest", "top case",
    "bottom case", "fan", "speaker", "wrist rest", "bezel",
    "repair", "replacement", "parts", "for parts", "not working",
    "broken", "damaged", "for repair", "as-is", "as is",
    "screen only", "cracked", "water damage",
    "defective", "faulty", "does not work", "doesn't work"
  ].freeze

  # iPhone accessory titles routinely name the exact phone they fit
  # ("Case for iPhone 15 Pro Max"), so a plain "does this mention the
  # generation" check can't tell them apart from a real phone the way
  # the MacBook keyword list can -- this list plus a required storage
  # figure (see electronics_relevant?) is what actually filters them.
  IPHONE_ACCESSORY_KEYWORDS = [
    "case", "cover", "skin", "decal", "sticker", "sleeve", "pouch",
    "screen protector", "tempered glass", "privacy glass", "camera lens",
    "charger", "charging cable", "cable", "adapter", "magsafe charger",
    "power bank", "battery pack", "car mount", "mount", "holder", "stand",
    "wallet", "lanyard", "strap", "pop socket", "popsocket", "stylus",
    "earbuds", "airpods", "headphones", "screen only", "lcd", "digitizer",
    "back glass", "housing", "flex cable", "logic board", "motherboard",
    "for parts", "repair part", "replacement part"
  ].freeze

  IPHONE_BAD_KEYWORDS = [
    "locked", "icloud", "activation lock",
    "for parts", "not working", "broken", "cracked", "damaged",
    "water damage", "for repair", "as is", "as-is", "parts only",
    "repair needed", "stolen", "blacklisted",
    "hardware locked", "sim locked", "carrier locked",
    "network locked", "bad imei",
    "defective", "faulty", "does not work", "doesn't work"
  ].freeze

  IPAD_ACCESSORY_KEYWORDS = [
    "case", "cover", "skin", "sleeve", "bag", "pouch", "shell",
    "screen protector", "tempered glass", "privacy glass",
    "charger", "charging cable", "cable", "adapter", "power bank",
    "keyboard", "keyboard case", "smart keyboard", "magic keyboard",
    "apple pencil", "stylus", "pen", "holder", "stand", "mount",
    "car mount", "arm", "tray", "dock", "docking station",
    "hub", "converter", "dongle",
    "repair", "replacement", "parts", "for parts", "not working",
    "broken", "damaged", "for repair", "as-is", "as is",
    "screen only", "cracked", "water damage",
    "defective", "faulty", "does not work", "doesn't work",
    "lcd", "digitizer", "flex cable", "ribbon cable",
    "logic board", "motherboard", "battery"
  ].freeze

  IPAD_BAD_KEYWORDS = [
    "locked", "icloud", "activation lock",
    "for parts", "not working", "broken", "cracked", "damaged",
    "water damage", "for repair", "as is", "as-is", "parts only",
    "repair needed", "stolen", "blacklisted",
    "defective", "faulty", "does not work", "doesn't work"
  ].freeze

  # `parse_electronics` runs every extractor below against one title and
  # hands back whatever it could find -- mirrors Python's
  # ElectronicsHandler#parse_specs. Any field it couldn't determine
  # comes back nil rather than raising, most titles are missing at
  # least one of these.
  def self.parse_electronics(title)
    cpu_cores, gpu_cores = extract_core_counts(title)
    {
      ram_gb: extract_ram_gb(title),
      storage_gb: extract_storage_gb(title),
      screen_size: extract_screen_size(title),
      chip: extract_chip(title),
      cpu_cores: cpu_cores,
      gpu_cores: gpu_cores
    }
  end

  # Looks for "128GB"/"128 GB" near a RAM-ish keyword first (most
  # reliable), then falls back to any bare "N GB" that matches one of
  # Apple's real RAM configurations, matches Python's extract_ram_gb.
  def self.extract_ram_gb(title)
    match = title.match(/(\d+)\s*GB\s*(?:RAM|Memory|Unified\s*Memory)/i) ||
            title.match(/(?:RAM|Memory|Unified\s*Memory)[:\s]*(\d+)\s*GB/i)
    if match
      value = match[1].to_i
      return value if value <= 256
    end

    all_gb = title.scan(/(\d+)\s*GB/i).flatten.map(&:to_i)
    real_ram_sizes = [ 8, 16, 24, 32, 36, 48, 64, 96, 128, 192 ]
    found = all_gb.find { |value| real_ram_sizes.include?(value) }
    return found if found

    all_gb.find { |value| value <= 256 }
  end

  # "N TB" always means storage; short of that, "N GB" next to
  # "SSD"/"Storage", or any bare "N GB" of 256+ (the smallest real
  # MacBook Pro drive) -- matches Python's extract_storage_gb.
  def self.extract_storage_gb(title)
    tb_match = title.match(/(\d+)\s*TB\s*(?:SSD)?/i)
    return tb_match[1].to_i * 1024 if tb_match

    gb_storage = title.match(/(\d+)\s*GB\s*(?:SSD|Storage)/i)
    if gb_storage
      value = gb_storage[1].to_i
      return value if value >= 256
    end

    title.scan(/(\d+)\s*GB/i).flatten.map(&:to_i).find { |value| value >= 256 }
  end

  # '14-inch', '14 inch', or a bare '14"' -- matches Python's
  # extract_screen_size.
  def self.extract_screen_size(title)
    match = title.match(/(\d+(?:\.\d+)?)[\s-]*inch/i) || title.match(/(\d+(?:\.\d+)?)"/)
    match && match[1].to_f
  end

  # "M5 Max", "M4 Pro", or a bare "M5" -- uses M\d{1,2} (not a
  # hardcoded M1-M5 range) so a future M6/M7 chip parses correctly with
  # no code change, matches Python's extract_chip exactly.
  def self.extract_chip(title)
    match = title.match(/(M\d{1,2}\s*(?:Pro|Max|Ultra))/i)
    return match[1].strip if match

    match = title.match(/\b(M\d{1,2})\b/i)
    match ? match[1].strip : nil
  end

  # Apple's standard spec phrasing, "16-Core CPU and 40-Core GPU" --
  # matches Python's extract_core_counts.
  def self.extract_core_counts(title)
    cpu_match = title.match(/(\d+)[\s‑-]*Core\s*CPU/i)
    gpu_match = title.match(/(\d+)[\s‑-]*Core\s*GPU/i)
    [ cpu_match && cpu_match[1].to_i, gpu_match && gpu_match[1].to_i ]
  end

  # `electronics_relevant?` rejects accessory/off-topic listings before
  # real spec matching runs -- which keyword list and rule applies
  # depends on which product this search is actually looking for.
  # Matches Python's ElectronicsHandler#is_relevant.
  def self.electronics_relevant?(title, condition, product_name)
    if product_name.include?("MacBook")
      likely_macbook_pro?(title, condition)
    elsif product_name.include?("iPhone")
      likely_iphone?(title, condition)
    elsif product_name.include?("iPad")
      likely_ipad_pro?(title, condition)
    else
      true
    end
  end

  def self.likely_macbook_pro?(title, condition = nil)
    title_lower = title.downcase
    condition_lower = condition.to_s.downcase
    return false unless title_lower.include?("macbook pro")
    return false if MACBOOK_ACCESSORY_KEYWORDS.any? { |kw| title_lower.include?(kw) || condition_lower.include?(kw) }

    has_chip = title.match?(/M\d{1,2}\s*(?:Pro|Max|Ultra)/i)
    has_screen = title.match?(/\d{2}\s*[‑-]?\s*inch/i) || title.match?(/\d{2}"/)
    has_ram = title.match?(/\d+\s*GB\s*(?:RAM|Memory|Unified)/i)
    has_storage = title.match?(/\d+\s*(?:TB|GB)\s*(?:SSD|Storage)/i)

    has_chip || has_screen || has_ram || has_storage
  end

  def self.likely_iphone?(title, condition = nil)
    title_lower = title.downcase
    condition_lower = condition.to_s.downcase
    return false unless title_lower.include?("iphone")
    return false if IPHONE_ACCESSORY_KEYWORDS.any? { |kw| title_lower.include?(kw) || condition_lower.include?(kw) }

    locked = title_lower.include?("locked") && !title_lower.include?("unlocked")
    return false if locked
    return false if IPHONE_BAD_KEYWORDS.any? { |kw| kw != "locked" && (title_lower.include?(kw) || condition_lower.include?(kw)) }

    # A real phone listing almost always states its storage capacity;
    # accessories almost never do -- the more reliable signal here.
    title.match?(/\d+\s*(?:GB|TB)\b/i)
  end

  def self.likely_ipad_pro?(title, condition = nil)
    title_lower = title.downcase
    condition_lower = condition.to_s.downcase
    return false unless title_lower.include?("ipad pro")
    return false if IPAD_ACCESSORY_KEYWORDS.any? { |kw| title_lower.include?(kw) || condition_lower.include?(kw) }

    locked = title_lower.include?("locked") && !title_lower.include?("unlocked")
    return false if locked
    return false if IPAD_BAD_KEYWORDS.any? { |kw| kw != "locked" && (title_lower.include?(kw) || condition_lower.include?(kw)) }

    has_chip = title.match?(/M\d{1,2}\s*(?:Pro|Max|Ultra)?/i)
    has_screen = title.match?(/\d+(?:\.\d+)?[\s-]*inch/i) || title.match?(/\d+(?:\.\d+)?"/)
    has_ram = title.match?(/\d+\s*GB\s*(?:RAM|Memory|Unified)/i)
    has_storage = title.match?(/\d+\s*(?:TB|GB)\s*(?:SSD|Storage)/i)

    has_chip || has_screen || has_ram || has_storage
  end

  # ── E-bike ────────────────────────────────────────────────────────

  # Reputable e-bike brands worth a small scoring bonus -- not an
  # exclusion list, an unlisted brand is still eligible, it just scores
  # no brand bonus. A direct port of ebike.py's KNOWN_BRANDS.
  EBIKE_KNOWN_BRANDS = [
    "Lectric", "Tern", "Brompton", "Rad Power", "RadPower", "Aventon",
    "Ride1Up", "Ride 1Up", "Blix", "Velotric", "REI Co-op", "Specialized",
    "Trek", "Electra", "Cannondale", "ENGWE", "Himiway", "Heybike",
    "AIPAS", "ET.Cycle", "ET Cycle", "Vtuvia", "Mokwheel", "Fiido",
    "Eunorau", "Juiced", "Magnum", "Pedego", "Addmotor", "Surface 604"
  ].freeze

  EBIKE_STEP_THROUGH_KEYWORDS = [
    "step thru", "step-thru", "step through", "step-through",
    "stepthru", "stepthrough", "low step"
  ].freeze

  EBIKE_ACCESSORY_KEYWORDS = [
    "battery only", "charger only", "frame only", "shell only",
    "for parts", "parts bike", "no battery", "no motor", "motor only",
    "display only", "controller only", "case only"
  ].freeze

  EBIKE_BAD_CONDITION_KEYWORDS = [
    "as-is", "as is", "for parts", "does not hold charge",
    "dead battery", "won't turn on", "wont turn on", "non-functional",
    "doesn't charge", "does not charge", "not charging"
  ].freeze

  # `parse_ebike` mirrors `parse_electronics` above but for the e-bike
  # search -- a direct port of ebike.py's EbikeHandler#parse_specs.
  def self.parse_ebike(title)
    motor_nominal, motor_peak = extract_motor_watts(title)
    voltage, ah = extract_battery_voltage_ah(title)
    battery_wh = (voltage && ah) ? (voltage * ah).round(1) : nil

    {
      brand: extract_ebike_brand(title),
      wheel_size_in: extract_wheel_size_in(title),
      fat_tire: extract_fat_tire(title),
      step_through: extract_step_through(title),
      folding: extract_folding(title),
      battery_voltage: voltage,
      battery_ah: ah,
      battery_wh: battery_wh,
      motor_watts_nominal: motor_nominal,
      motor_watts_peak: motor_peak,
      weight_capacity_lb: extract_weight_capacity_lb(title),
      brake_type: extract_brake_type(title),
      suspension: extract_suspension(title),
      ul_certified: extract_ul_certified(title)
    }
  end

  def self.extract_ebike_brand(title)
    title_lower = title.downcase
    EBIKE_KNOWN_BRANDS.find { |brand| title_lower.include?(brand.downcase) }
  end

  # Only ever returns 16/20/24 (the rider brief's target sizes) -- this
  # is a bonus signal for those three sizes specifically, not a general
  # wheel-size extractor, matches ebike.py's extract_wheel_size_in.
  def self.extract_wheel_size_in(title)
    match = title.match(/\b(16|20|24)\s*(?:x\s*\d(?:\.\d)?)?[\s-]*(?:inch|in\b|")/i) ||
            title.match(/\b(16|20|24)x\d/i)
    match && match[1].to_f
  end

  def self.extract_fat_tire(title)
    title_lower = title.downcase
    return true if title_lower.include?("fat tire") || title_lower.include?("fat-tire") || title_lower.include?("fattire")

    match = title_lower.match(/\b\d{2}\s*x\s*(\d(?:\.\d)?)\b/)
    match ? match[1].to_f.between?(3.0, 4.5) : false
  end

  # Title-keyword signal ONLY -- never a verified frame-geometry
  # confirmation. See ebike.py's module docstring STEP-THROUGH CAVEAT:
  # a low-frame marketing claim is not the same thing as a confirmed
  # true step-through geometry.
  def self.extract_step_through(title)
    title_lower = title.downcase
    EBIKE_STEP_THROUGH_KEYWORDS.any? { |kw| title_lower.include?(kw) }
  end

  def self.extract_folding(title)
    title_lower = title.downcase
    %w[folding fold-up foldable].any? { |kw| title_lower.include?(kw) } || title_lower.include?("fold up") || title_lower.include?("fold")
  end

  # "48V 20Ah" / "36V/10.4Ah" -- both bounded to plausible e-bike
  # battery ranges so a stray unrelated number in the title doesn't get
  # mistaken for a spec, matches ebike.py's extract_battery_voltage_ah.
  def self.extract_battery_voltage_ah(title)
    voltage = nil
    ah = nil

    v_match = title.match(/\b(\d{2,3})\s*V\b/i)
    if v_match
      value = v_match[1].to_i
      voltage = value if value.between?(24, 72)
    end

    ah_match = title.match(/\b(\d{1,2}(?:\.\d)?)\s*Ah\b/i)
    if ah_match
      value = ah_match[1].to_f
      ah = value if value.between?(3, 40)
    end

    [ voltage, ah ]
  end

  # Distinguishes a stated PEAK figure ("1200W peak") from a NOMINAL
  # one ("750W nominal", or just a bare "750W" with no qualifier at
  # all -- the common case). Never silently treats an unqualified
  # number as peak, matches ebike.py's extract_motor_watts and its
  # NOMINAL VS. PEAK MOTOR WATTAGE docstring section exactly.
  def self.extract_motor_watts(title)
    peak = nil
    nominal = nil

    peak_match = title.match(/(\d{3,4})\s*W\w*\s*(?:peak|max)/i)
    peak = peak_match[1].to_i if peak_match

    nominal_match = title.match(/(\d{3,4})\s*W\w*\s*(?:nominal|continuous|rated)/i)
    nominal = nominal_match[1].to_i if nominal_match

    if nominal.nil?
      title.scan(/(\d{3,4})\s*W(?!att)\b/i) do |(value_str)|
        value = value_str.to_i
        tail = title[($~.end(0))...($~.end(0) + 12)].to_s.downcase
        next if tail.include?("peak") || tail.include?("max")
        next if peak && value == peak
        next unless value.between?(200, 3000)

        nominal = value
        break
      end
    end

    [ nominal, peak ]
  end

  def self.extract_brake_type(title)
    title_lower = title.downcase
    return "hydraulic" if title_lower.include?("hydraulic")
    return "mechanical" if title_lower.include?("mechanical disc") || title_lower.include?("disc brake")
    return "rim" if title_lower.include?("rim brake")

    nil
  end

  def self.extract_suspension(title)
    title.downcase.include?("suspension")
  end

  def self.extract_ul_certified(title)
    title.downcase.match?(/ul\s*-?\s*2849|ul\s*-?\s*2271|ul\s+certified|ul-certified/)
  end

  # A stated weight/load capacity like "400lb capacity" -- deliberately
  # requires a capacity/limit/load keyword nearby so this doesn't
  # confuse a bike's own shipping weight (also often in lb) for its
  # rated rider capacity, matches ebike.py's extract_weight_capacity_lb.
  def self.extract_weight_capacity_lb(title)
    match = title.match(/(\d{3})\s*(?:lb|lbs)\.?\s*(?:capacity|weight\s*limit|load\s*capacity|max\s*(?:weight|load))/i) ||
            title.match(/(?:capacity|weight\s*limit|load\s*capacity|max\s*(?:weight|load))\s*(?:of\s*)?(\d{3})\s*(?:lb|lbs)\.?/i)
    match && match[1].to_i
  end

  # `ebike_relevant?` rejects accessory/off-topic listings and bikes in
  # unrideable condition -- matches ebike.py's EbikeHandler#is_relevant.
  def self.ebike_relevant?(title, condition = nil)
    title_lower = title.downcase
    condition_lower = condition.to_s.downcase

    return false if EBIKE_ACCESSORY_KEYWORDS.any? { |kw| title_lower.include?(kw) || condition_lower.include?(kw) }
    return false if EBIKE_BAD_CONDITION_KEYWORDS.any? { |kw| title_lower.include?(kw) || condition_lower.include?(kw) }

    true
  end
end
