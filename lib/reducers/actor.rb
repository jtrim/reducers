module Reducers
  class Actor
    extend Forwardable # For convenience params delegation
    attr_accessor :params, :result

    private_class_method :new # private to protect from accidentally skipping preconditions

    def self.precondition(precondition_method_name)
      @precondition_method_name = precondition_method_name
    end
    private_class_method :precondition

    def self.precondition_config
      @precondition_method_name
    end
    private_class_method :precondition_config

    def self.no_params
      @params_config = []
      @required_params_config = []
    end
    private_class_method :no_params

    def self.params(*incoming_param_names)
      params_config = if incoming_param_names.first.is_a?(Hash)
                        incoming_param_names.first
                      else
                        Array(incoming_param_names).map { |c| [c, :optional] }.to_h
                      end
      if (unknown_configs = params_config.map(&:last).uniq - [:required, :optional]).any?
        raise "Unknown parameter configuration: #{unknown_configs.inspect}. Must be one of :required, :optional"
      end
      @params_config ||= []
      @params_config += params_config.keys
      @required_params_config ||= []
      @required_params_config += params_config.select { |_, requirement| requirement.to_sym == :required }.map(&:first)
      # Define convenience delegators to params
      def_delegators :params, *@params_config
    end
    private_class_method :params

    def self.no_result
      @required_result_config = []
    end
    private_class_method :no_result

    def self.result(*outgoing_result_names)
      @required_result_config ||= []
      @required_result_config += outgoing_result_names
    end
    private_class_method :result

    def self.params_config # rubocop:disable Style/TrivialAccessors
      @params_config
    end

    def self.required_params_config # rubocop:disable Style/TrivialAccessors
      @required_params_config
    end

    def self.required_result_config # rubocop:disable Style/TrivialAccessors
      @required_result_config
    end

    def self.call(**args)
      raise Errors::ImplicitConfigurationError if params_config.nil? || required_result_config.nil?

      instance = new(args)

      begin
        assert_valid_keys instance,
                          requirement:      required_params_config,
                          actual:           args.keys,
                          message_template: '%s is required'

        if precondition_config
          if (precondition_result = instance.public_send(precondition_config))
            Reducers.logger.info "Actor #{self} was executed with params: #{pretty_params(instance.params)} : precondition #{precondition_config.inspect} evaluated to #{precondition_result}"
          else
            Reducers.logger.info "Actor #{self} was skipped with params: #{pretty_params(instance.params)} : precondition #{precondition_config.inspect} evaluated to #{precondition_result}"

            instance.result.skipped = true
            return instance.result.to_h
          end
        else
          Reducers.logger.info "Actor #{self} was executed: no precondition defined"
        end

        instance.call
        # TODO: Should an exception result from invalid result keys instead?
        assert_valid_keys instance,
                          requirement:      required_result_config,
                          actual:           instance.result.to_h.keys,
                          message_template: 'Actor implementation did not set required result: %s'
        assert_valid_keys instance,
                          requirement:      instance.result.to_h.keys - [:successful, :messages],
                          actual:           required_result_config,
                          message_template: 'Actor implementation set undeclared result: %s'
      rescue Reducers::Errors::DieInterceptError
        # no-op: die is called to halt actor execution. NOTE: it's important that this is a 'raise/rescue' instead of a
        # 'throw/catch' to ensure things like block-style database transactions correctly roll back when 'die' is called
        nil
      end

      instance.result.to_h
    end

    def self.pretty_params(params)
      params.to_h.map { |k, v| [k, v.inspect[0..50]] }.to_h
    end

    def self.call!(**args)
      call(**args).tap do |result|
        raise Errors::FailureError, result[:messages] unless result[:successful]
      end
    end

    def self.assert_valid_keys(instance, requirement:, actual:, message_template:)
      unsatisfied_keys = requirement - actual
      unsatisfied_keys.each do |required_key_name|
        instance.add_message(message_template % required_key_name.inspect)
      end
      instance.die if unsatisfied_keys.any?
    end
    private_class_method :assert_valid_keys

    def initialize(params)
      @params = OpenStruct.new(params)
      @result = OpenStruct.new(successful: true, messages: [])
    end

    def call(*)
      raise NotImplementedError
    end

    def reduce_with(**args, &block)
      reducer          = Reducer.create(&block)
      reducer_result   = reducer.call(**args)
      desired_keys     = self.class.required_result_config + [:successful]
      desired_result   = desired_keys.zip(reducer_result.values_at(*desired_keys)).to_h.reject { |_, v| v.nil? }
      reducer_messages = reducer_result.delete(:messages)
      self.result      = OpenStruct.new(result.to_h.merge(desired_result))
      add_message reducer_messages
    end

    def die(message_or_messages = nil)
      result.successful = false
      add_message(message_or_messages) if message_or_messages
      Reducers.logger.warn("#{self.class} failed on 'die' with messages #{result.messages.inspect} and params: #{self.class.pretty_params(params)}")
      raise Reducers::Errors::DieInterceptError
    end

    def add_message(msg)
      result.messages += Array(msg)
    end
  end
end
