# frozen_string_literal: true

module Sqdash
  module Models
    class Job < ActiveRecord::Base
      self.table_name = "solid_queue_jobs"

      has_one :failed_execution, class_name: "Sqdash::Models::FailedExecution", foreign_key: :job_id
      has_one :ready_execution, class_name: "Sqdash::Models::ReadyExecution", foreign_key: :job_id
    end
  end
end
