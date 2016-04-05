# encoding: utf-8

require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/ruby"
require "logstash/filters/date"

describe LogStash::Filters::Ruby do

  describe "modifying deeply nested values with ruby syntax" do
    config <<-CONFIG
      filter {
        ruby {
          code => "event['parent']['child'] = 'foobar'"
        }
      }
    CONFIG

    sample("parent" => {"child" => "foo"}) do
      insist { subject["parent"]["child"] } == "foobar"
    end
  end

  describe "accessing the field with alternating syntax and mutation" do
    config <<-CONFIG
      filter {
        ruby {
          code => "event['parent']['child'] << 'bar'; event['[parent][child]'] << 'baz'"
        }
      }
    CONFIG

    sample("parent" => {"child" => "foo"}) do
      insist { subject["parent"]["child"] } == "foobarbaz"
    end
  end

  describe "accessing the field with alternating syntax and assignment" do
    config <<-CONFIG
      filter {
        ruby {
          code => "event['parent']['child'] += 'bar'; event['[parent][child]'] += 'baz'"
        }
      }
    CONFIG

    sample("parent" => {"child" => "foo"}) do
      insist { subject["parent"]["child"] } == "foobarbaz"
    end
  end

  describe "modifying deeply nested values with logstash" do
    config <<-CONFIG
      filter {
        ruby {
          code => "event['[parent][child]'] = 'foobar'"
        }
      }
    CONFIG

    sample("parent" => {"child" => "foo"}) do
      insist { subject["parent"]["child"] } == "foobar"
    end
  end

  describe "in place modifications" do
    config <<-CONFIG
      filter {
        ruby {
          code => "event['myval'].downcase!"
        }
      }
    CONFIG

    sample("myval" => "FOO") do
      insist { subject["myval"] } == "foo"
    end
  end

  describe "generate pretty json on event.to_hash" do
    # this obviously tests the Ruby filter but also makes sure
    # the fix for issue #1771 is correct and that to_json is
    # compatible with the json gem convention.
    #
    config <<-CONFIG
      filter {
        date {
          match => [ "mydate", "ISO8601" ]
          locale => "en"
          timezone => "UTC"
        }
        ruby {
          init => "require 'json'"
          code => "event['pretty'] = JSON.pretty_generate(event.to_hash)"
        }
      }
    CONFIG
    #
    sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
      # json is rendered in pretty json since the JSON.pretty_generate created json from the event hash
      # pretty json contains \n
      insist { subject["pretty"].count("\n") } == 5
      # usage of JSON.parse here is to avoid parser-specific order assertions
      insist { JSON.parse(subject["pretty"]) } == JSON.parse("{\n  \"message\": \"hello world\",\n  \"mydate\": \"2014-09-23T00:00:00-0800\",\n  \"@version\": \"1\",\n  \"@timestamp\": \"2014-09-23T08:00:00.000Z\"\n}")
    end
  end
    #
  describe "generate pretty json on event.to_hash" do
    # this obviously tests the Ruby filter but asses that using the json gem directly
    # on even will correctly call the to_json method but will use the logstash json
    # generation and thus will not work with pretty_generate.
    config <<-CONFIG
      filter {
        date {
          match => [ "mydate", "ISO8601" ]
          locale => "en"
          timezone => "UTC"
        }
        ruby {
          init => "require 'json'"
          code => "event['pretty'] = JSON.pretty_generate(event)"
        }
      }
    CONFIG

    sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
      # if this eventually breaks because we removed the custom to_json and/or added pretty support to JrJackson then all is good :)
      # non-pretty json does not contain \n
      insist { subject["pretty"].count("\n") } == 0
      # usage of JSON.parse here is to avoid parser-specific order assertions
      insist { JSON.parse(subject["pretty"]) } == JSON.parse("{\"message\":\"hello world\",\"mydate\":\"2014-09-23T00:00:00-0800\",\"@version\":\"1\",\"@timestamp\":\"2014-09-23T08:00:00.000Z\"}")
    end
  end

  describe "catch all exceptions and don't let them ruin your day buy stopping the entire worker" do
    # If exception is raised, it stops entine processing pipeline, and never resumes
    # Code section should always be wrapped with begin/rescue
    config <<-CONFIG
      filter {
        date {
          match => [ "mydate", "ISO8601" ]
          locale => "en"
          timezone => "UTC"
        }
        ruby {
          init => "require 'json'"
          code => "raise 'You shall not pass'"
          add_tag => ["ok"]
        }
      }
    CONFIG

    sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
      insist { subject["mydate"] } == "2014-09-23T00:00:00-0800"
      insist { subject["tags"] } == ["_rubyexception"]
    end
  end
end

