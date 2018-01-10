module Reducers
  module ActorDSL
    KW_TYPES = { key: :optional, keyreq: :required }.freeze

    def actor(result: [], params: {}, precondition: nil)
      @capture_next_method = true
      @next_actor_options = { result: result, params: params, precondition: precondition, precondition_name: :passes_precondition? }
    end

    def precondition(name, &block)
      raise Errors::ActorDSLPreconditionDefinitionOrderError unless @capture_next_method
      @next_actor_options = @next_actor_options.merge(precondition: block, precondition_name: name)
    end

    def method_added(method_name)
      add_actor(method_name) if @capture_next_method
    end

    private

    def add_actor(name)
      method = instance_method(name)
      if method.parameters.any?
        raise Errors::DualParameterDefinitionError, name if @next_actor_options[:params].any?
        @next_actor_options[:params] = method.parameters.map do |param_type, key|
          # TODO: what else could there be? :keyreq and :key are the two I saw in Pry
          [key, KW_TYPES.fetch(param_type)]
        end.to_h
      end

      next_actor_options = @next_actor_options
      klass = Class.new(Reducers::Actor) do
        if next_actor_options[:params].any?
          params(next_actor_options[:params])
        else
          no_params
        end

        if next_actor_options[:result].any?
          result(*next_actor_options[:result])
        else
          no_result
        end

        if next_actor_options[:precondition]
          precondition next_actor_options[:precondition_name]
        end
      end

      klass.class_eval(transform_method_to_call(method), *method.source_location)

      if next_actor_options[:precondition]
        klass.send(:define_method, next_actor_options[:precondition_name], next_actor_options[:precondition])
      end

      const_set(name, klass)
      undef_method(name)
      @capture_next_method = false
      @next_actor_options  = {}
    end

    # @param method [UnboundMethod] the method that has the method signature to modify
    # @return [String] the source of a method that has had its signature changed to `def call`
    def transform_method_to_call(method)
      ast = Parser::CurrentRuby.parse(method.source)
      new_ast = Parser::AST::Node.new(:def, [:call, Parser::AST::Node.new(:args, []), ast.children.last])
      Unparser.unparse(new_ast)
    end
  end
end
