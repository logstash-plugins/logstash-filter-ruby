# encoding: utf-8

require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/ruby"
require "logstash/filters/date"

describe LogStash::Filters::Ruby do

  describe "generate pretty json on event.to_hash" do
    # this obviously tests the Ruby filter but also makes sure
    # the fix for issue #1771 is correct and that to_json is
    # compatible with the json gem convention.

    config <<-CONFIG
      filter {
        date {
          match => [ "mydate", "ISO8601" ]
          locale => "en"
          timezone => "UTC"
        }
        ruby {
          init => "require 'json'"
          code => "event.set('pretty', JSON.pretty_generate(event.to_hash))"
        }
      }
    CONFIG

    sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
      # json is rendered in pretty json since the JSON.pretty_generate created json from the event hash
      # pretty json contains \n
      insist { subject.get("pretty").count("\n") } == 5
      # usage of JSON.parse here is to avoid parser-specific order assertions
      insist { JSON.parse(subject.get("pretty")) } == JSON.parse("{\n  \"message\": \"hello world\",\n  \"mydate\": \"2014-09-23T00:00:00-0800\",\n  \"@version\": \"1\",\n  \"@timestamp\": \"2014-09-23T08:00:00.000Z\"\n}")
    end
  end

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
          code => "event.set('pretty', JSON.pretty_generate(event))"
        }
      }
    CONFIG

    sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
      # if this eventually breaks because we removed the custom to_json and/or added pretty support to JrJackson then all is good :)
      # non-pretty json does not contain \n
      insist { subject.get("pretty").count("\n") } == 0
      # usage of JSON.parse here is to avoid parser-specific order assertions
      insist { JSON.parse(subject.get("pretty")) } == JSON.parse("{\"message\":\"hello world\",\"mydate\":\"2014-09-23T00:00:00-0800\",\"@version\":\"1\",\"@timestamp\":\"2014-09-23T08:00:00.000Z\"}")
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
      insist { subject.get("mydate") } == "2014-09-23T00:00:00-0800"
      insist { subject.get("tags") } == ["_rubyexception"]
    end
  end

  describe "allow to create new event inside the ruby filter" do
    config <<-CONFIG
      filter {
        ruby {
          code => "new_event_block.call(event.clone)"
        }
      }
    CONFIG

    sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
      expect(subject).to be_a Array
      expect(subject[0]).not_to eq(subject[1])
      expect(subject[0].to_hash).to eq(subject[1].to_hash)
    end
  end

  describe "allow to replace event by another one" do
    config <<-CONFIG
      filter {
        ruby {
          code => "new_event_block.call(event.clone);
                   event.cancel;"
          add_tag => ["ok"]
        }
      }
    CONFIG

    sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
      expect(subject.get("message")).to eq("hello world");
      expect(subject.get("mydate")).to eq("2014-09-23T00:00:00-0800");
    end
  end

  describe "allow custom tagging of failed code execution" do
    # If exception is raised, it stops entine processing pipeline, and never resumes
    # Code section should always be wrapped with begin/rescue
    config <<-CONFIG
      filter {
        ruby {
          code => "raise 'Chuck Norris says you cannot pass.'"
          tag_on_failure => ["_chuck_norris_exception"]
        }
      }
    CONFIG

    sample("message" => "Chuck Norris does not worry about high gas prices. His vehicles run on fear.") do
      insist { subject.get("tags") } == ["_chuck_norris_exception"]
    end
  end
end

