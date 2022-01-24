# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/ruby"
require "logstash/filters/date"

describe LogStash::Filters::Ruby do
  context "when using inline script" do
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
        insist { JSON.parse(subject.get("pretty")) } == JSON.parse("{\n  \"message\": \"hello world\",\n  \"mydate\": \"2014-09-23T00:00:00-0800\",\n  \"@version\": \"1\",\n  \"@timestamp\": \"#{get_logstash_timestamp("2014-09-23T08:00:00.000Z")}\"\n}")
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
        insist { JSON.parse(subject.get("pretty")) } == JSON.parse("{\"message\":\"hello world\",\"mydate\":\"2014-09-23T00:00:00-0800\",\"@version\":\"1\",\"@timestamp\":\"#{get_logstash_timestamp("2014-09-23T08:00:00.000Z")}\"}")
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

    describe "with new event block" do
      subject(:filter) { ::LogStash::Filters::Ruby.new('code' => 'new_event_block.call(event.clone)') }
      before(:each) { filter.register }

      it "creates new event" do
        event = LogStash::Event.new "message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800"
        new_events = filter.multi_filter([event])
        expect(new_events.length).to eq 2
        expect(new_events[0]).to equal(event)
        expect(new_events[1]).not_to eq(event)
        expect(new_events[1].to_hash).to eq(event.to_hash)
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
  end

  context "when using file based script" do
    let(:fixtures_path) { File.join(File.dirname(__FILE__), '../fixtures/') }
    let(:script_filename) { 'field_multiplier.rb' }
    let(:script_path) { File.join(fixtures_path, script_filename)}
    let(:script_params) { { 'field' => 'foo', 'multiplier' => 2 } }
    let(:filter_params) { { 'path' => script_path, 'script_params' => script_params} }
    let(:incoming_event) { ::LogStash::Event.new('foo' => 42) }

    subject(:filter) { ::LogStash::Filters::Ruby.new(filter_params) }

    describe "basics" do
      it "should register cleanly" do
        expect do
          filter.register
        end.not_to raise_error
      end

      describe "filtering" do
        let(:filter_params) { super().merge('add_field' => {'success' => 'yes' }) }
        before(:each) do
          filter.register
          filter.filter(incoming_event)
        end

        it "should filter data as expected" do
          expect(incoming_event.get('foo')).to eq(84)
        end

        it "should apply filter_matched" do
          expect(incoming_event.get('success')).to eq('yes')
        end
      end
    end

    describe "scripts with failing test suites" do
      let(:script_filename) { 'broken.rb' }

      it "should error out during register" do
        expect do
          filter.register
        end.to raise_error(LogStash::Filters::Ruby::ScriptError)
      end
    end

    describe "scripts with failing test suites" do
      let(:script_filename) { 'multi_events.rb' }

      it "should produce more multiple events" do
        expect {|b| filter.filter(incoming_event, &b) }.to yield_control.exactly(3).times
      end
    end
  end
end
