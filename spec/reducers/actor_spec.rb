require 'reducers'

RSpec.describe Reducers::Actor do
  around do |ex|
    Reducers.logger.silence { ex.run }
  end

  it 'has params and a result' do
    expect(described_class.send(:new, { foo: 'bar' }).params).to eq(OpenStruct.new({ foo: 'bar' }))
    expect(described_class.send(:new, {}).result).to eq(OpenStruct.new(successful: true, messages: []))
  end

  it 'does not expose ::new so that preconditions cannot be bypassed' do
    expect {
      described_class.new({})
    }.to raise_error NoMethodError
  end

  describe '::params' do
    it 'allows defining all-optional params via an array' do
      actor = Class.new(described_class) do
        params :foo, :bar
        no_result

        def call; end
      end

      expect(actor.params_config).to eq [:foo, :bar]
      expect(actor.required_params_config).to eq []
    end

    it 'allows specifying multiple varying parameter requirements with a hash' do
      actor = Class.new(described_class) do
        params foo: :required
        no_result

        def call; end
      end

      expect(actor.params_config).to eq [:foo]
      expect(actor.required_params_config).to eq [:foo]
    end

    it 'allows specifying multiple varying parameter requirements with a hash' do
      actor = Class.new(described_class) do
        params foo: :required, bar: :optional
        no_result

        def call; end
      end

      expect(actor.params_config).to eq [:foo, :bar]
      expect(actor.required_params_config).to eq [:foo]
    end

    it 'defines convenience delegators on the instance for params (to reduce boilerplate params._)' do
      actor = Class.new(described_class) do
        params :incoming_foo
        result :outgoing_foo

        def call
          result.outgoing_foo = incoming_foo
        end
      end

      result = actor.call(incoming_foo: 'F00')

      expect(result[:successful]).to be true
      expect(result[:outgoing_foo]).to eq 'F00'
    end
  end

  describe '::call' do
    it 'fails on missing required params' do
      actor = Class.new(described_class) do
        params foo: :required
        no_result
      end

      result = actor.call({})
      expect(result[:successful]).to be false
      expect(result[:messages]).to include(/:foo is required/i)
    end

    it 'evaluates parameter requirements before running precondition logic' do
      actor = Class.new(described_class) do
        params foo: :required, call_spy: :required
        no_result
        precondition :foo?

        def foo?
          call_spy.called!
          true
        end
      end

      call_spy = spy
      result = actor.call(call_spy: call_spy)
      expect(result[:successful]).to be false
      expect(result[:messages]).to include(/:foo is required/i)
      expect(call_spy).not_to have_received(:called!)
    end

    it 'allows optional params to be blank' do
      actor = Class.new(described_class) do
        params foo: :optional
        no_result
        def call; end
      end

      result = actor.call
      expect(result[:successful]).to be true
      expect(result[:messages]).to be_empty
    end

    it 'fails on an unset result param' do
      actor = Class.new(described_class) do
        no_params
        result :foo
        def call; end
      end

      result = actor.call
      expect(result[:successful]).to be false
      expect(result[:messages]).to include(/Actor implementation did not set required result: :foo/i)
    end

    # See https://github.com/wunderteam/portal/pull/1895#discussion_r150036873
    it 'allows multiple calls to param for incremental configuration' do
      actor = Class.new(described_class) do
        params foo: :required
        params bar: :required
        no_result

        def call; end
      end

      result = actor.call
      expect(result[:successful]).to be false
      expect(result[:messages]).to match [a_string_matching(/:foo is required/i), a_string_matching(/:bar is required/i)]
    end

    it 'fails on an extra undeclared result param' do
      actor = Class.new(described_class) do
        no_params
        no_result
        def call
          result.foo = 'undeclared'
        end
      end

      result = actor.call
      expect(result[:successful]).to be false
      expect(result[:messages]).to include(/Actor implementation set undeclared result: :foo/i)
    end

    # See https://github.com/wunderteam/portal/pull/1895#discussion_r150036873
    it 'allows multiple calls to result for incremental configuration' do
      actor = Class.new(described_class) do
        no_params
        result :foo
        result :bar

        def call; end
      end

      result = actor.call
      expect(result[:successful]).to be false
      expect(result[:messages])
        .to match [
              a_string_matching(/Actor implementation did not set required result: :foo/i),
              a_string_matching(/Actor implementation did not set required result: :bar/i)
            ]
    end

    describe 'precondition behavior' do
      it 'executes when no precondition is defined' do
        actor = Class.new(described_class) do
          params :foo
          no_result

          def call
            params.foo.called!
          end
        end

        param = spy
        actor.call(foo: param)

        expect(param).to have_received(:called!)
      end

      it 'executes when a defined precondition returns something truthy' do
        actor = Class.new(described_class) do
          precondition :foo?
          params :foo
          no_result

          def call
            params.foo.called!
          end

          def foo?
            "true"
          end
        end

        param = spy
        actor.call(foo: param)

        expect(param).to have_received(:called!)
      end

      it 'skips execution when a defined precondition returns something falsy' do
        actor = Class.new(described_class) do
          precondition :foo?
          params :foo
          no_result

          def call
            params.foo.called!
          end

          def foo?
            nil
          end
        end

        param = spy
        result = actor.call(foo: param)

        expect(param).not_to have_received(:called!)
        expect(result).to include(successful: true, skipped: true)
      end

      it 'logs a message on execution with no precondition' do
        actor = Class.new(described_class) do
          no_params
          no_result
          def call; end
        end

        expect(Reducers.logger).to receive(:info).with(a_string_matching(/Actor .* was executed: no precondition defined/i))

        actor.call
      end

      it 'logs a message on execution with a passing precondition' do
        actor = Class.new(described_class) do
          params :bar
          no_result

          precondition :foo?

          def call; end

          def foo?
            true
          end
        end

        expect(Reducers.logger).to receive(:info).with(a_string_matching(/Actor .* was executed with params: {:bar=>.*quux.*} : precondition :foo\? evaluated to true/i))

        actor.call(bar: 'quux')
      end

      it 'logs a message on skipped execution with a failing precondition' do
        actor = Class.new(described_class) do
          params :bar
          no_result

          precondition :foo?

          def call; end

          def foo?
            false
          end
        end

        expect(Reducers.logger).to receive(:info).with(a_string_matching(/Actor .* was skipped with params: {:bar=>.*quux.*} : precondition :foo\? evaluated to false/i))

        actor.call(bar: 'quux')
      end

      context 'when adding messages in a precondition' do
        it 'includes the messages in the result when the precondition fails' do
          actor = Class.new(described_class) do
            precondition :foo?
            no_params
            no_result
            def call; end

            def foo?
              add_message 'Skipped: foo'
              false
            end
          end

          result = actor.call
          expect(result).to match(
                              successful: true,
                              skipped:    true,
                              messages:   ['Skipped: foo']
                            )
        end
      end
    end

    it 'raises an exception when params are not configured' do
      actor = Class.new(described_class) do
        no_result
        def call; end
      end

      expect { actor.call }.to raise_error Reducers::Errors::ImplicitConfigurationError
    end

    it 'raises an exception when result is not configured' do
      actor = Class.new(described_class) do
        no_params
        def call; end
      end

      expect { actor.call }.to raise_error Reducers::Errors::ImplicitConfigurationError
    end
  end

  describe '::call!' do
    it 'executes an actor' do
      actor = Class.new(described_class) do
        no_params
        no_result

        def call
          params.foo.called!
        end
      end

      param = spy
      actor.call!(foo: param)

      expect(param).to have_received(:called!)
    end

    it 'raises an exception when the actor operation is unsuccessful' do
      actor = Class.new(described_class) do
        no_params
        no_result
        def call
          die %w[Intentionally left blank]
        end
      end

      expect {
        actor.call!
      }.to raise_error Reducers::Errors::FailureError, /Actor operation failed: Intentionally, left, blank/i
    end

    it 'returns the actor result on success' do
      actor = Class.new(described_class) do
        no_params
        result :foo
        def call
          result.foo = 'bar'
        end
      end

      result = actor.call!
      expect(result).to match a_hash_including(successful: true)
    end
  end

  describe '#die' do
    subject { described_class.send(:new, {}) }

    it 'adds a message to the actor and raises' do
      expect {
        subject.die('something happened')
      }.to raise_error Reducers::Errors::DieInterceptError
    end

    it 'adds multiple messages to the actor and raises' do
      subject.die(['something happened', 'oh no']) rescue Reducers::Errors::DieInterceptError
      expect(subject.result[:messages]).to eq ['something happened', 'oh no']
    end

    it 'drops a log message with diagnostic details' do
      expect(Reducers.logger).to receive(:warn).with(
                                   /Reducers::Actor failed on 'die' with messages \["something happened", "oh no"\]/i)
      subject.die(['something happened', 'oh no']) rescue Reducers::Errors::DieInterceptError
    end
  end

  describe '#add_message' do
    subject { described_class.send(:new, {}) }

    it 'adds a message to the actor' do
      subject.add_message('foo')
      expect(subject.result[:messages]).to eq ['foo']
    end

    it 'adds multiple messages to the actor at once' do
      subject.add_message(['foo', 'bar'])
      expect(subject.result[:messages]).to eq ['foo', 'bar']
    end
  end

  describe '#reduce_with' do
    before do
      Reducers::ActorCleanRoom1 = Class.new(described_class) do
        no_params
        no_result
        def call; end
      end

      Reducers::ActorCleanRoom2 = Class.new(described_class) do
        no_params
        no_result
        def call; end
      end
      allow(Reducers::ActorCleanRoom1).to receive(:call).and_return(successful: true)
      allow(Reducers::ActorCleanRoom2).to receive(:call).and_return(successful: true)
    end

    after do
      ::Reducers.send(:remove_const, :ActorCleanRoom1)
      ::Reducers.send(:remove_const, :ActorCleanRoom2)
    end

    it 'builds and invokes a reducer with the arguments given to reduce_with' do
      reducer_spy = spy(call: { successful: true })
      allow(Reducers::Reducer).to receive(:new).and_return(reducer_spy)

      actor = Class.new(described_class) do
        no_params
        no_result

        def call
          reduce_with(foo: 'bar') do
            add ::Reducers::ActorCleanRoom1
            add ::Reducers::ActorCleanRoom2
          end
        end
      end

      actor.call

      expect(reducer_spy).to have_received(:add).with(Reducers::ActorCleanRoom1).once.ordered
      expect(reducer_spy).to have_received(:add).with(Reducers::ActorCleanRoom2).once.ordered

      expect(reducer_spy).to have_received(:call).once.ordered.with(a_hash_including(foo: 'bar'))
    end

    it 'merges the reducer result into the actor result' do
      reducer_spy = spy(call: { successful: true, foo: 'bar', baz: 'bif' })
      allow(Reducers::Reducer).to receive(:new).and_return(reducer_spy)

      actor = Class.new(described_class) do
        no_params
        result :foo, :baz

        def call
          reduce_with # no-op because the test double is already configured with a return value
        end
      end

      result = actor.call
      expect(result).to match(successful: true, foo: 'bar', baz: 'bif', messages: [])
    end

    it 'accumulates messages from the reducer' do
      reducer_spy = spy(call: { successful: false, messages: ['in reducer'] })
      allow(Reducers::Reducer).to receive(:new).and_return(reducer_spy)

      actor = Class.new(described_class) do
        no_params
        no_result

        def call
          add_message 'in actor'
          reduce_with # no-op because the test double is already configured with a return value
        end
      end

      result = actor.call
      expect(result).to match(a_hash_including(messages: ['in actor', 'in reducer']))
    end
  end
end
