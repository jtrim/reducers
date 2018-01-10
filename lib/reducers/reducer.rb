module Reducers
  class Reducer < Organizer
    def actors
      super.map(&:first) # TODO: not optimal. Is this the point where a Reducer is no longer an Organizer?
    end

    def call(**args)
      ensure_no_reserved_keys(args)
      ensure_parameter_continuity_requirements(args)

      results = args.merge(successful: true, messages: [])

      around_proc.call do
        actors.each do |actor|
          actor_result = actor.call(**results)
          messages     = results[:messages] + Array(actor_result[:messages])
          results      = results.merge(actor_result).merge(messages: messages)

          unless results[:successful]
            on_failure_proc&.call(actor_result)
            break
          end
        end
      end

      results
    end

    private

    def ensure_no_reserved_keys(initial_args)
      %w[successful messages].each do |reserved_parameter_name|
        raise Errors::ReservedParameterError, reserved_parameter_name if initial_args.keys.map(&:to_s).include?(reserved_parameter_name)
      end
    end

    def ensure_parameter_continuity_requirements(initial_args)
      accumulated_param_keys = initial_args.keys
      actors.each do |actor|
        unsatisfied_param_keys = actor.required_params_config - accumulated_param_keys

        raise Errors::UnproducedParameterError.new(actor, self, initial_args.keys, unsatisfied_param_keys) if unsatisfied_param_keys.any?
        accumulated_param_keys += actor.required_result_config
      end
    end
  end
end
