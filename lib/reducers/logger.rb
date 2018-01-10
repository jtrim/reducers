module Reducers
  class Logger
    attr_accessor :info_logger, :warn_logger, :error_logger

    def initialize(default_logger = ConsoleLogger)
      @info_logger = @warn_logger = @error_logger = default_logger
    end

    def silence
      displaced_loggers = [@info_logger, @warn_logger, @error_logger]
      @info_logger = @warn_logger = @error_logger = NullLogger
      yield
    ensure
      @info_logger, @warn_logger, @error_logger = displaced_loggers
    end

    def warn(message)
      warn_logger.log "WARNING: #{message}"
    end

    def info(message)
      info_logger.log "INFO: #{message}"
    end

    def error(message)
      error_logger.log "ERROR: #{message}"
    end

    module ConsoleLogger
      def self.log(message, io = STDERR)
        io.puts message
      end
    end

    class NullLogger
      def self.log(*); end
    end
  end
end
