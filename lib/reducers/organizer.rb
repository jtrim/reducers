module Reducers
  class Organizer
    attr_reader :actors

    DEFAULT_PRECONDITION = proc { true }
    SKIPPED_RESULT       = { successful: true, skipped: true, messages: [].freeze }.freeze

    def self.create(&block)
      new.tap do |instance|
        instance.instance_eval(&block) if block_given?
      end
    end

    def initialize
      @actors          = []
      @around_proc     = proc { |&b| b.call }
      @on_failure_proc = nil
    end

    def add(actor, precondition: DEFAULT_PRECONDITION)
      @actors += [[actor, precondition]]
    end

    def around(&block)
      @around_proc = block
    end

    def on_failure(&block)
      @on_failure_proc = block
    end

    def call(**args)
      results = actors.map { nil }
      around_proc.call do
        actors.each.with_index do |(actor, precondition), i|
          precondition_result = precondition.call(**args)
          if precondition_result
            result = actor.call(**args)
            results[i] = result
            unless result[:successful]
              Reducers.logger.warn "Actor #{actor} failed within an organizer. Messages: #{result[:messages].inspect}"
              on_failure_proc&.call(result)
            end
          else
            warn_actor_skipped_on_organizer_precondition(actor, args, precondition_result)
            results[i] = SKIPPED_RESULT
          end
        end
      end
      results
    end

    def call!(**args)
      actors.map do |(actor, precondition)|
        precondition_result = precondition.call(**args)
        if precondition_result
          actor.call!(**args)
        else
          warn_actor_skipped_on_organizer_precondition(actor, args, precondition_result)
          SKIPPED_RESULT
        end
      end
    end

    private

    attr_reader :around_proc, :on_failure_proc

    def warn_actor_skipped_on_organizer_precondition(actor, args, precondition_result)
      Reducers.logger.info "Actor #{actor} was skipped by an organizer precondition with params: #{args.map { |k, v| [k, v.inspect[0..50]] }.to_h} : precondition evaluated to #{precondition_result}"
    end
  end
end
