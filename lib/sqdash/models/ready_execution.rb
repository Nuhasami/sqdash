# frozen_string_literal: true

module Sqdash
  module Models
    class ReadyExecution < ActiveRecord::Base
      self.table_name = "solid_queue_ready_executions"
    end
  end
end
