# frozen_string_literal: true

module Sqd
  module Models
    class ReadyExecution < ActiveRecord::Base
      self.table_name = "solid_queue_ready_executions"
    end
  end
end
