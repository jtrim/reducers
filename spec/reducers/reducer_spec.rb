require 'reducers'

RSpec.describe Reducers::Reducer do
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

  describe '#call' do
    context 'for an empty reduction' do
      it 'includes a base-level set of values in the resulting hash' do
        expect(subject.call).to eq(successful: true, messages: [])
      end
    end

    it 'raises an error when reserved keys are included in the initial arguments' do
      expect {
        subject.call(successful: "foo")
      }.to raise_error(Reducers::Errors::ReservedParameterError, /incoming parameter not allowed: successful/)

      expect {
        subject.call(messages: "foo")
      }.to raise_error(Reducers::Errors::ReservedParameterError, /incoming parameter not allowed: messages/)
    end

    it 'passes parameters accumulated from the result of prior actors into subsequent actors' do
      actor1 = create_noop_actor
      allow(actor1).to receive(:call) { { foo: 'bar' } }
      actor2 = create_noop_actor
      allow(actor2).to receive(:call) { { baz: 'bif' } }
      actor3 = create_noop_actor
      allow(actor3).to receive(:call) { {} }

      subject.add(actor1)
      subject.add(actor2)
      subject.add(actor3)

      subject.call

      expect(actor1).to have_received(:call).with(successful: true, messages: [])
      expect(actor2).to have_received(:call).with(foo: 'bar', successful: true, messages: [])
      expect(actor3).to have_received(:call).with(foo: 'bar', baz: 'bif', successful: true, messages: [])
    end

    it 'returns the accumulated result' do
      actor1 = create_noop_actor
      allow(actor1).to receive(:call) { { foo: 'bar' } }
      actor2 = create_noop_actor
      allow(actor2).to receive(:call) { { baz: 'bif' } }

      subject.add(actor1)
      subject.add(actor2)

      expect(subject.call).to eq(foo: 'bar', baz: 'bif', successful: true, messages: [])
    end

    it 'accumulates messages' do
      actor1 = create_noop_actor
      allow(actor1).to receive(:call) { { messages: ['message one'] } }
      actor2 = create_noop_actor
      allow(actor2).to receive(:call) { { messages: ['message two', 'message three'] } }

      subject.add(actor1)
      subject.add(actor2)

      expect(subject.call)
        .to eq(successful: true, messages: ['message one', 'message two', 'message three'])
    end

    describe 'preserving parameter continuity' do
      it 'can satisfy parameter continuity requirements from both initial params and those produced by preceding actors' do
        actor1 = Class.new(Reducers::Actor) do
          no_params
          result :foo
          def call
            result.foo = 'bar'
          end
        end

        actor2 = Class.new(Reducers::Actor) do
          params foo: :required, bar: :required
          no_result
          def call; end
        end

        subject.add(actor1)
        subject.add(actor2)

        expect {
          subject.call(bar: 'baz')
        }.not_to raise_error
      end

      context 'when not all actors in the reduction will have the parameters they require' do
        it 'raises an exception' do
          actor1 = Class.new(Reducers::Actor) do
            no_params
            result :foo
            def call
              result.foo = 'bar'
            end
          end

          actor2 = Class.new(Reducers::Actor) do
            params foo: :required, bar: :required
            no_result
            def call; end
          end

          subject.add(actor1)
          subject.add(actor2)

          expect {
            subject.call
          }.to raise_error(/Actor .* included in reducer .* requires parameters that are never produced by a preceding actor. Unproduced parameter\(s\): \[:bar\]. Initial param keys: \[\]/i)
        end
      end
    end

    context 'when an actor emits an unsuccessful result' do
      it 'short-circuits the reduction' do
        actor1 = create_noop_actor
        allow(actor1).to receive(:call) { { successful: false } }
        actor2 = create_noop_actor
        allow(actor2).to receive(:call) { {} }

        subject.add(actor1)
        subject.add(actor2)

        expect(subject.call(foo: 'bar')).to eq(foo: 'bar', successful: false, messages: [])

        expect(actor1).to have_received(:call)
        expect(actor2).not_to have_received(:call)
      end
    end

    context 'when an around block is specified' do
      it 'invokes the actor chain within the context of the around block' do
        call_spy = spy
        actor1 = create_noop_actor
        allow(actor1).to receive(:call) { { successful: true } }
        actor2 = create_noop_actor
        allow(actor2).to receive(:call) { { successful: true } }

        subject.add(actor1)
        subject.add(actor2)

        subject.around do |&actor|
          call_spy.called!
          actor.call
        end

        result = subject.call

        expect(result).to eq(successful: true, messages: [])
        expect(call_spy).to have_received(:called!)
      end
    end

    context 'when an on_failure block is specified' do
      it 'invokes on_failure block when an actor fails' do
        call_spy = spy
        actor1 = create_noop_actor
        allow(actor1).to receive(:call) { { successful: false } }
        actor2 = create_noop_actor

        subject.add(actor1)
        subject.add(actor2)

        subject.on_failure do
          call_spy.called!
        end

        result = subject.call

        expect(result).to eq(successful: false, messages: [])
        expect(call_spy).to have_received(:called!)
      end

      it 'passes the result to the on_failure proc' do
        actor1 = create_noop_actor
        allow(actor1).to receive(:call) { { successful: false, messages: ['foo'] } }

        subject.add(actor1)

        messages = nil
        subject.on_failure do |result|
          messages = result[:messages]
        end

        subject.call

        expect(messages).to eq ['foo']
      end
    end

    context 'when #on_failure raises an exception caught in #around' do
      it 'still returns the expected results hash' do
        fake_error = Class.new(StandardError)

        subject.around do |&actors|
          begin
            actors.call
          rescue fake_error
            nil
          end
        end

        subject.on_failure do
          raise fake_error
        end

        actor1 = create_noop_actor
        allow(actor1).to receive(:call) { { successful: false, messages: ['foo'] } }
        actor2 = create_noop_actor
        allow(actor2).to receive(:call) { { successful: true, something: 'else' } }

        subject.add(actor1)
        subject.add(actor2)

        result = subject.call(incoming: 'param')

        expect(result).to eq(successful: false, messages: ['foo'], incoming: 'param')
      end
    end
  end
end
