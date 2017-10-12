def filter(event)
  event.set('foo', 'bar')
  [event]
end

test "setting the field" do
  in_event { { "myfield" => 123 } }

  # This should fail!
  expect("foo to equal baz") do |events|
    events.first.get('foo') == 'baz'
  end
end
