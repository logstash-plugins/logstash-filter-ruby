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
        expect( subject.get("pretty").count("\n") ).to eql 5
        # usage of JSON.parse here is to avoid parser-specific order assertions
        expect( JSON.parse(subject.get("pretty")) ).to eql JSON.parse("{\n  \"message\": \"hello world\",\n  \"mydate\": \"2014-09-23T00:00:00-0800\",\n  \"@version\": \"1\",\n  \"@timestamp\": \"2014-09-23T08:00:00.000Z\"\n}")
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
        expect( subject.get("pretty").count("\n") ).to eql 0
        # usage of JSON.parse here is to avoid parser-specific order assertions
        expect( JSON.parse(subject.get("pretty")) ).to eql JSON.parse("{\"message\":\"hello world\",\"mydate\":\"2014-09-23T00:00:00-0800\",\"@version\":\"1\",\"@timestamp\":\"2014-09-23T08:00:00.000Z\"}")
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
        expect( subject.get("mydate") ).to eql "2014-09-23T00:00:00-0800"
        expect( subject.get("tags") ).to eql ["_rubyexception"]
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

    describe "code raising" do

      let(:event) { LogStash::Event.new "message" => "hello world" }
      let(:code) { 'raise "an_error"' }

      subject(:filter) { ::LogStash::Filters::Ruby.new('code' => code) }
      before(:each) { filter.register }

      it "should handle (standard) error" do
        expect( filter.logger ).to receive(:error).
            with('Exception occurred: an_error', hash_including(:exception => RuntimeError)).
            and_call_original

        new_events = filter.multi_filter([event])
        expect(new_events.length).to eq 1
        expect(new_events[0]).to equal(event)
        expect( event.get('tags') ).to eql [ '_rubyexception' ]
      end

      context 'fatal error' do

        let(:code) { 'raise java.lang.AssertionError.new("TEST")' }

        it "should not rescue Java errors" do
          expect( filter.logger ).to_not receive(:error)

          expect { filter.multi_filter([event]) }.to raise_error(java.lang.AssertionError)
        end
      end
    end

    describe "invalid script" do
      let(:filter_params) { { 'code' => code } }
      subject(:filter) { ::LogStash::Filters::Ruby.new(filter_params) }

      let(:code) { 'sample do syntax error' }

      it "should error out during register" do
        expect { filter.register }.to raise_error(SyntaxError)
      end

      it "reports correct error line" do
        begin
          filter.register
          fail('syntax error expected')
        rescue SyntaxError => e
          expect( e.message ).to match /\(ruby filter code\):1.*? unexpected end-of-file/
        end
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

    describe "script that raises" do
      let(:script_filename) { 'raising.rb' }

      before(:each) do
        filter.register
        incoming_event.set('error', 'ERR-MSG')
      end

      it "should handle (standard) error" do
        expect( filter.logger ).to receive(:error).
            with('Could not process event:', hash_including(:message => 'ERR-MSG', :exception => NameError)).
            and_call_original
        filter.filter(incoming_event)
        expect( incoming_event.get('tags') ).to eql [ '_rubyexception' ]
      end
    end

    describe "invalid .rb script" do
      let(:script_filename) { 'invalid.rb' }

      it "should error out during register" do
        expect { filter.register }.to raise_error(SyntaxError)
      end

      it "should report correct line number" do
        begin
          filter.register
          fail('syntax error expected')
        rescue SyntaxError => e
          expect( e.message ).to match /invalid\.rb\:7/
        end
      end
    end
  end
end
