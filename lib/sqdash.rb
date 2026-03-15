# frozen_string_literal: true

require_relative "sqdash/version"
require_relative "sqdash/database"
require_relative "sqdash/models/job"
require_relative "sqdash/models/failed_execution"
require_relative "sqdash/models/ready_execution"
require_relative "sqdash/cli"

module Sqdash
  class Error < StandardError; end
end
