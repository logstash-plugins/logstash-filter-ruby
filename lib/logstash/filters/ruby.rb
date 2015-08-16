# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

# Execute ruby code.
#
# For example, to cancel 90% of events, you can do this:
# [source,ruby]
#     filter {
#       ruby {
#         # Cancel 90% of events
#         code => "event.cancel if rand <= 0.90"
#       }
#     }
#
# If you need to create additional events, it cannot be done as in other filters where you would use `yield`,
# you must use a specific syntax `new_event_block.call(event)` like in this example duplicating the input event
# [source,ruby]
# filter {
#   ruby {
#     code => "new_event_block.call(event.clone)"
#   }
# }
#
class LogStash::Filters::Ruby < LogStash::Filters::Base
  config_name "ruby"

  # Any code to execute at logstash startup-time
  config :init, :validate => :string

  # The code to execute for every event.
  # You will have an `event` variable available that is the event itself.
  config :code, :validate => :string, :required => true

  def register
    # TODO(sissel): Compile the ruby code
    eval(@init, binding, "(ruby filter init)") if @init
    eval("@codeblock = lambda { |event, &new_event_block| #{@code} }", binding, "(ruby filter code)")
  end # def register

  def filter(event,&block)
    begin
      @codeblock.call(event,&block)
      filter_matched(event)
    rescue Exception => e
      @logger.error("Ruby exception occurred: #{e}")
      event.tag("_rubyexception")
    end
  end
end
