class LogstashEventProxy
  def initialize(event)
    @event = event
    @cached_fields = {}
    @cache_needs_flush = false
  end

  def [](name)
    flush_cached_fields! if @cache_needs_flush
    if name.include?("[")
      flush_cached_fields!
      @cache_needs_flush = true
    end

    if (cached = @cached_fields[name])
      cached
    else
      orig = @event[name]
      @cached_fields[name] = orig
      orig
    end
  end

  def []=(name,val)
    flush_cached_fields! if @cache_needs_flush
    @cache_needs_flush = true if name.include?("[")

    @cached_fields[name] = val
    flush_cached_fields! if @cache_needs_flush
    val
  end

  # Flush all cached to orig event
  def flush_cached_fields!
    @cached_fields.each do |k,v|
      @event[k] = v
    end
    @cache_needs_flush = false
    @cached_fields.clear
  end

  def proxied_event
    @event
  end

  own_methods = (self.instance_methods - Object.instance_methods) + [:initialize]
  logstash_event_methods = ::LogStash::Event.instance_methods - own_methods

  logstash_event_methods.each do |method_name|
    method_code = proc do |*args|
      flush_cached_fields!
      @event.send(method_name,*args)
    end
    define_method(method_name, method_code)
  end

end