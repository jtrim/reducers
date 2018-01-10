module Reducers
  module Errors
    class ReducerError < StandardError
    end

    class ReservedParameterError < ReducerError
      def initialize(param_name)
        @param_name = param_name
      end

      def to_s
        "incoming parameter not allowed: #{@param_name}"
      end
    end

    class FailureError < ReducerError
      def initialize(messages)
        @messages = messages
      end

      def to_s
        "Actor operation failed: #{@messages.join(', ')}"
      end
    end

    class DieInterceptError < ReducerError
      def to_s
        'Used to halt actor#call on failure. Rescued by Actor::call'
      end
    end

    class UnproducedParameterError < ReducerError
      def initialize(actor, reducer, initial_param_keys, unproduced_param_keys)
        @actor                 = actor
        @reducer               = reducer
        @initial_param_keys    = initial_param_keys
        @unproduced_param_keys = unproduced_param_keys
      end

      def to_s
        "Actor #{@actor.inspect} included in reducer #{@reducer.inspect} requires parameters that are " \
        "never produced by a preceding actor. Unproduced parameter(s): #{@unproduced_param_keys.inspect}. " \
        "Initial param keys: #{@initial_param_keys.inspect}"
      end
    end

    class DualParameterDefinitionError < ReducerError
      def initialize(name)
        @name = name
      end

      def to_s
        "ActorDSL definition for #{@name} attempts to define param keys both via actor params: { ... } and method arguments. Only one form is allowed"
      end
    end

    class ActorDSLPreconditionDefinitionOrderError < ReducerError
      def to_s
        '`precondition` must be invoked after `actor` but before the method definition when using ActorDSL'
      end
    end

    class ImplicitConfigurationError < ReducerError
      def to_s
        'Params and result must be explicitly configured! Either call params ... or no_params / result ... or no_result'
      end
    end
  end
end
