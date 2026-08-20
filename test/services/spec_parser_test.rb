require "test_helper"

class SpecParserTest < ActiveSupport::TestCase
  test "parse_electronics pulls RAM, storage, screen size, chip, and core counts out of a real title" do
    title = 'Apple MacBook Pro 14" M5 Max Chip 128GB Unified Memory 2TB SSD - 16-Core CPU and 40-Core GPU'
    specs = SpecParser.parse_electronics(title)

    assert_equal 128, specs[:ram_gb]
    assert_equal 2048, specs[:storage_gb] # 2TB
    assert_equal 14.0, specs[:screen_size]
    assert_equal "M5 Max", specs[:chip]
    assert_equal 16, specs[:cpu_cores]
    assert_equal 40, specs[:gpu_cores]
  end

  test "extract_storage_gb never confuses RAM with storage" do
    # 128GB RAM here, 2TB SSD there -- both numbers are GB-ish, but
    # only one of them is storage.
    assert_equal 2048, SpecParser.extract_storage_gb("128GB RAM / 2TB SSD")
    assert_nil SpecParser.extract_storage_gb("128GB RAM only, no storage mentioned")
  end

  test "extract_chip matches known suffixed chips and future-proof bare M-numbers" do
    assert_equal "M5 Max", SpecParser.extract_chip("MacBook Pro M5 Max 128GB")
    assert_equal "M4 Pro", SpecParser.extract_chip("MacBook Pro M4 Pro 48GB")
    # No hardcoded M1-M5 cutoff -- a future M9 still parses.
    assert_equal "M9", SpecParser.extract_chip("MacBook Pro M9 128GB")
  end

  test "likely_macbook_pro? rejects accessories that mention MacBook Pro" do
    assert SpecParser.likely_macbook_pro?('MacBook Pro 14" M5 Max 128GB 2TB')
    assert_not SpecParser.likely_macbook_pro?("MacBook Pro 14 inch Hard Shell Case")
    assert_not SpecParser.likely_macbook_pro?("Just a MacBook, not the Pro model")
  end

  test "likely_iphone? requires a stated storage capacity, not just the model name" do
    assert SpecParser.likely_iphone?("Apple iPhone 17 Pro Max 256GB Unlocked")
    assert_not SpecParser.likely_iphone?("Case for iPhone 17 Pro Max")
    assert_not SpecParser.likely_iphone?("iPhone 17 Pro Max 256GB iCloud Locked")
  end

  test "parse_ebike pulls brand, wheel size, battery, and motor specs out of a real title" do
    title = "Lectric XPedition 20x4 Fat Tire Folding Step-Thru E-Bike 48V 20Ah 750W Nominal 1200W Peak"
    specs = SpecParser.parse_ebike(title)

    assert_equal "Lectric", specs[:brand]
    assert_equal 20.0, specs[:wheel_size_in]
    assert specs[:fat_tire]
    assert specs[:step_through]
    assert specs[:folding]
    assert_equal 48, specs[:battery_voltage]
    assert_equal 20.0, specs[:battery_ah]
    assert_equal 960.0, specs[:battery_wh]
    assert_equal 750, specs[:motor_watts_nominal]
    assert_equal 1200, specs[:motor_watts_peak]
  end

  test "extract_motor_watts treats an unqualified wattage as nominal, never silently as peak" do
    nominal, peak = SpecParser.extract_motor_watts("Aventon Level.2 Commuter E-Bike 750W Motor")
    assert_equal 750, nominal
    assert_nil peak
  end

  test "extract_weight_capacity_lb requires a nearby capacity keyword, not a bare number" do
    assert_equal 400, SpecParser.extract_weight_capacity_lb("Rated 400lb capacity fat tire e-bike")
    assert_nil SpecParser.extract_weight_capacity_lb("Bike ships at 400lb in the crate")
  end

  test "ebike_relevant? rejects accessory-only and dead-battery listings" do
    assert SpecParser.ebike_relevant?("Lectric XPedition Folding E-Bike", nil)
    assert_not SpecParser.ebike_relevant?("Lectric XPedition battery only", nil)
    assert_not SpecParser.ebike_relevant?("Lectric XPedition, does not hold charge", nil)
  end
end
