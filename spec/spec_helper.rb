# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "insist"

module TestHelper
  def get_logstash_timestamp(expected)
    expected = LogStash::Timestamp.new(expected)
    expected.to_s
  end
end

RSpec.configure do |config|
  config.include TestHelper
end