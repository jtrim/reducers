require 'ostruct'
require 'forwardable'

require 'method_source'
require 'parser'
require 'unparser'

require 'reducers/version'
require 'reducers/errors'
require 'reducers/logger'
require 'reducers/organizer'
require 'reducers/reducer'
require 'reducers/actor'
require 'reducers/actor_dsl'

module Reducers
  def self.logger
    @logger ||= Logger.new
  end

  def self.logger=(val)
    @logger = val
  end
end
