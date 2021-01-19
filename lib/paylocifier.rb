require 'paylocifier/version'
require 'paylocifier/config'
require 'paylocifier/client'

require 'paylocifier/collection'
require 'paylocifier/models/employee'
require 'paylocifier/models/earning'

module Paylocifier
  class Error < StandardError; end

  def self.configure
    yield config
  end

  def self.config
    @@config ||= Paylocifier::Config.new
  end
end
