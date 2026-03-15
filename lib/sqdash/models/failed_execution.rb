# frozen_string_literal: true

module Sqdash
  module Models
    class FailedExecution < ActiveRecord::Base
      self.table_name = "solid_queue_failed_executions"

      belongs_to :job, class_name: "Sqdash::Models::Job"

      def retry!
        transaction do
          ReadyExecution.create!(
            job_id: job_id,
            queue_name: job.queue_name,
            priority: job.priority
          )
          destroy!
        end
      end

      def discard!
        transaction do
          job.update!(finished_at: Time.now)
          destroy!
        end
      end
    end
  end
end
