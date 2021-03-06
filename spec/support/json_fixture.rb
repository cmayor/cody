require 'json'

module JsonFixture
  def json_fixture(path)
    JSON.load(File.open(Rails.root.join("spec", "fixtures", "#{path}.json")))
  end
end

RSpec.configure do |config|
  config.include JsonFixture
end
