require 'reducers'

RSpec.describe Reducers::Organizer do
  def create_noop_actor(*)
    Class.new(Reducers::Actor) do
      no_params
      no_result
      def call; end
    end
  end

  around do |ex|
    Reducers.logger.silence { ex.run }
  end

  describe '::create' do
    it 'returns a new organizer' do
      expect(described_class.create).to be_a described_class
    end

    it 'evals the supplied block against the new organizer' do
      organizer_spy = spy
      allow(described_class).to receive(:new).and_return(organizer_spy)
      described_class.create do
        add 'foo'
      end
      expect(organizer_spy).to have_received(:add).with('foo')
    end

    specify 'all features still work in the block "create" form' do
      fake_actor1    = double(:actor1, call: { successful: true, messages: [] })
      fake_actor2    = double(:actor2, call: { successful: false, messages: ['whoops'] })
      around_spy     = spy(:around)
      on_failure_spy = spy(:on_failure)

      organizer = described_class.create do
        add fake_actor1
        add fake_actor2

        around do |&actor|
          around_spy.called!
          actor.call
        end

        on_failure do
          on_failure_spy.called!
        end
      end

      result = organizer.call

      expect(result).to eq [{ successful: true, messages: [] },
                            { successful: false, messages: ['whoops'] }]

      expect(fake_actor1).to have_received(:call)
      expect(fake_actor2).to have_received(:call)
      expect(around_spy).to have_received(:called!)
      expect(on_failure_spy).to have_received(:called!)
    end
  end

  describe '#around' do
    it 'registers a proc to wrap the #call execution in' do
      actor_spy     = spy
      call_spy      = spy
      fake_database = Class.new do
        def self.transaction
          yield
        end
      end

      subject.around do |&actor|
        call_spy.called!
        fake_database.transaction(&actor)
      end

      subject.add(actor_spy)
      subject.call

      expect(call_spy).to have_received(:called!)
      expect(actor_spy).to have_received(:call)
    end
  end

  describe '#on_failure' do
    it 'calls the registered on_fail proc when an actor is unsuccessful' do
      call_spy  = spy
      actor_spy = double(call: { successful: false })

      subject.on_failure do
        call_spy.called!
      end

      subject.add(actor_spy)

      subject.call

      expect(call_spy).to have_received(:called!)
    end

    it 'does not call the registered on_fail proc when an actor is successful' do
      call_spy  = spy
      actor_spy = double(call: { successful: true })

      subject.on_failure do
        call_spy.called!
      end

      subject.add(actor_spy)

      subject.call

      expect(call_spy).not_to have_received(:called!)
    end

    it 'passes on_failure the failed result' do
      actor_spy = double(call: { successful: false, messages: ['foo'] })

      messages = nil
      subject.on_failure do |result|
        messages = result[:messages]
      end

      subject.add(actor_spy)

      subject.call

      expect(messages).to eq ['foo']
    end

    it 'still returns an array of results from #call when #on_failure raises an exception caught in #around' do
      fake_error = Class.new(StandardError)

      subject.around do |&actor|
        begin
          actor.call
        rescue fake_error
          nil
        end
      end

      subject.on_failure do
        raise fake_error
      end

      subject.add(double(call: { successful: true, messages: ['message'] }))
      subject.add(double(call: { successful: false, messages: ['failure'] }))
      subject.add(spy)

      result = subject.call

      expect(result).to eq [{ successful: true, messages: ['message'] },
                            { successful: false, messages: ['failure'] },
                            nil]
    end
  end

  describe '#add' do
    it 'adds an actor to the call chain' do
      subject.add('foo')
      subject.add('bar')
      subject.add('baz')

      expect(subject.actors.map(&:first)).to eq %w[foo bar baz]
    end

    it 'accepts a precondition that only applies to the given actor in the context of the subject organizer' do
      call_spy = spy

      subject.add(actor1 = spy(call: { successful: true }))
      subject.add(actor2 = spy(call: { successful: true }), precondition: ->(the_call_spy:) { the_call_spy.called!; false }) # rubocop:disable Style/Semicolon
      subject.add(actor3 = spy(call: { successful: true }))

      subject.call(the_call_spy: call_spy)

      expect(call_spy).to have_received(:called!)
      expect(actor1).to have_received(:call)
      expect(actor2).not_to have_received(:call)
      expect(actor3).to have_received(:call)
    end
  end

  describe '#call' do
    it 'calls #call on a list of actors' do
      actor1 = spy
      actor2 = spy
      actor3 = spy

      subject.add(actor1)
      subject.add(actor2)
      subject.add(actor3)

      subject.call

      expect(actor1).to have_received(:call).once.ordered
      expect(actor2).to have_received(:call).once.ordered
      expect(actor3).to have_received(:call).once.ordered
    end

    it 'calls each actor with arguments supplied to #call' do
      subject.add(actor = spy)
      subject.call(foo: 'bar')
      expect(actor).to have_received(:call).with(foo: 'bar')
    end

    it 'returns a list of the return values from each actor' do
      actor1 = double(call: { first: 'first', successful: true })
      actor2 = double(call: { second: 'second', successful: true })
      actor3 = double(call: { third: 'third', successful: true })

      subject.add(actor1)
      subject.add(actor2)
      subject.add(actor3)

      expect(subject.call).to eq [{ first: 'first', successful: true },
                                  { second: 'second', successful: true },
                                  { third: 'third', successful: true }]
    end

    it 'emits a log warning message when an actor fails' do
      actor1 = double(call: { first: 'first', successful: true })
      actor2 = double(call: { second: 'second', successful: false, messages: ['something went wrong'] })
      actor3 = double(call: { third: 'third', successful: true })

      subject.add(actor1)
      subject.add(actor2)
      subject.add(actor3)

      expect(Reducers.logger).to receive(:warn).with(a_string_matching(/Actor .* failed within an organizer. Message(s): \["something went wrong"\]/i))

      subject.call
    end
  end

  describe '#call!' do
    it 'raises an error when an actor fails' do
      actor1 = create_noop_actor
      actor2 = Class.new(Reducers::Actor) do
        no_params
        no_result
        def call
          die 'something went wrong'
        end
      end
      actor3 = create_noop_actor

      subject.add(actor1)
      subject.add(actor2)
      subject.add(actor3)

      expect {
        subject.call!
      }.to raise_error Reducers::Errors::FailureError, /Actor operation failed: something went wrong/i
    end

    it 'halts computation' do
      actor1 = create_noop_actor
      allow(actor1).to receive(:call!)
      actor2 = Class.new(Reducers::Actor) do
        no_params
        no_result
        def call
          die 'something went wrong'
        end
      end
      actor3 = create_noop_actor
      allow(actor3).to receive(:call!)

      subject.add(actor1)
      subject.add(actor2)
      subject.add(actor3)

      subject.call! rescue nil

      expect(actor1).to have_received(:call!)
      expect(actor3).not_to have_received(:call!)
    end
  end
end
