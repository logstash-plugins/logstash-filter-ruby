def register(params)
end

def filter(event)
  raise NameError, event.get('error') if event.get('error')
  event
end