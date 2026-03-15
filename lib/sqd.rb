# frozen_string_literal: true

require_relative "sqd/version"
require_relative "sqd/database"
require_relative "sqd/models/job"
require_relative "sqd/models/failed_execution"
require_relative "sqd/models/ready_execution"
require_relative "sqd/cli"

module Sqd
  class Error < StandardError; end
end
