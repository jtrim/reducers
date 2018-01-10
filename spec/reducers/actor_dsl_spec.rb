require 'reducers'

module Reducers
  RSpec.describe ActorDSL do
    around do |ex|
      Reducers.logger.silence { ex.run }
    end

    it 'can derive an actor from a method' do
      stage = Module.new do
        extend ActorDSL

        actor
        def DoSomething; end # rubocop:disable Style/MethodName
      end

      expect(stage::DoSomething.ancestors).to include(Reducers::Actor)
    end

    it 'does not create an actor unless `actor` is invoked' do
      stage = Module.new do
        extend ActorDSL

        def DoSomething; end # rubocop:disable Style/MethodName
      end

      expect {
        stage::DoSomething
      }.to raise_error NameError
    end

    it 'does not create two actors from one `actor` invocation' do
      stage = Module.new do
        extend ActorDSL

        actor
        def DoSomething; end # rubocop:disable Style/MethodName

        def SomethingElse; end # rubocop:disable Style/MethodName
      end

      expect(stage::DoSomething.ancestors).to include(Reducers::Actor)
      expect {
        stage::SomethingElse
      }.to raise_error NameError
    end

    specify 'multiple extensions of ActorDSL do not share configuration' do
      _stage1 = Module.new do
        extend ActorDSL

        actor
      end

      stage2 = Module.new do
        extend ActorDSL

        def DoSomething; end # rubocop:disable Style/MethodName
      end

      expect {
        stage2::DoSomething
      }.to raise_error NameError
    end

    describe 'actor properties' do
      it 'can assign result keys from arguments to `actor`' do
        stage = Module.new do
          extend ActorDSL

          actor result: [:foo]
          def DoSomething; end # rubocop:disable Style/MethodName
        end

        expect(stage::DoSomething.required_result_config).to eq [:foo]
      end

      it 'can assign param keys from arguments to `actor`' do
        stage = Module.new do
          extend ActorDSL

          actor params: { foo: :required, bar: :optional }
          def DoSomething; end # rubocop:disable Style/MethodName
        end

        expect(stage::DoSomething.params_config).to eq [:foo, :bar]
        expect(stage::DoSomething.required_params_config).to eq [:foo]
      end

      it 'can assign param keys from actor method args' do
        stage = Module.new do
          extend ActorDSL

          actor
          def DoSomething(foo:, bar: nil); end # rubocop:disable Style/MethodName
        end

        expect(stage::DoSomething.params_config).to eq [:foo, :bar]
        expect(stage::DoSomething.required_params_config).to eq [:foo]
      end

      it 'raises an exception if there are both params and method arguments' do
        expect do
          Module.new do
            extend ActorDSL

            actor params: { foo: :required }
            def DoSomething(foo:, bar: nil); end # rubocop:disable Style/MethodName
          end
        end.to raise_error Reducers::Errors::DualParameterDefinitionError, /ActorDSL definition for DoSomething attempts to define param keys both via/i
      end

      it 'defines an actor #call method based on the named actor method with no params' do
        stage = Module.new do
          extend ActorDSL

          actor result: [:foo]
          def DoSomething # rubocop:disable Style/MethodName
            result.foo = 'called!'
          end
        end

        result = stage::DoSomething.call
        expect(result[:successful]).to be true
        expect(result[:foo]).to eq 'called!'
      end

      it 'defines an actor #call method based on the named actor method with params' do
        stage = Module.new do
          extend ActorDSL

          actor result: [:bar]
          def DoSomething(foo:) # rubocop:disable Style/MethodName
            result.bar = foo
          end
        end

        result = stage::DoSomething.call(foo: 'quux')
        expect(result[:successful]).to be true
        expect(result[:bar]).to eq 'quux'
      end

      it 'cleans up the original named actor method definition' do
        stage = Module.new do
          extend ActorDSL
          actor
          def DoSomething; end # rubocop:disable Style/MethodName
        end

        expect(stage.instance_methods).not_to include :DoSomething
      end

      it 'can define a precondition method in the actor definition line' do
        stage = Module.new do
          extend ActorDSL

          actor precondition: -> { foo == 'foo' }
          def DoSomething(foo:); end # rubocop:disable Style/MethodName
        end

        expect_any_instance_of(stage::DoSomething).to receive(:call)
        stage::DoSomething.call(foo: 'foo')

        expect_any_instance_of(stage::DoSomething).not_to receive(:call)
        stage::DoSomething.call(foo: 'bar')
      end

      it 'can define a precondition method via `precondition`' do
        stage = Module.new do
          extend ActorDSL

          actor
          precondition(:foo?) { foo == 'foo' }
          def DoSomething(foo:); end # rubocop:disable Style/MethodName
        end

        expect_any_instance_of(stage::DoSomething).to receive(:call)
        stage::DoSomething.call(foo: 'foo')

        expect_any_instance_of(stage::DoSomething).not_to receive(:call)
        stage::DoSomething.call(foo: 'bar')
      end

      it 'raises an exception when defining a precondition out of order' do
        expect do
          Module.new do
            extend ActorDSL

            precondition(:foo?) { foo == 'foo' }
            actor
            def DoSomething(foo:); end # rubocop:disable Style/MethodName
          end
        end.to raise_error Errors::ActorDSLPreconditionDefinitionOrderError
      end
    end
  end
end
