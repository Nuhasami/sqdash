# frozen_string_literal: true

require_relative "../test_helper"

class JobTest < Minitest::Test
  def setup
    Sqdash::Models::ReadyExecution.delete_all
    Sqdash::Models::FailedExecution.delete_all
    Sqdash::Models::Job.delete_all

    @job = Sqdash::Models::Job.create!(
      class_name: "TestJob",
      queue_name: "default",
      priority: 5
    )
  end

  def test_has_one_failed_execution
    failed = Sqdash::Models::FailedExecution.create!(job_id: @job.id, error: "boom")

    assert_equal failed, @job.failed_execution
  end

  def test_has_one_ready_execution
    ready = Sqdash::Models::ReadyExecution.create!(
      job_id: @job.id,
      queue_name: @job.queue_name,
      priority: @job.priority
    )

    assert_equal ready, @job.ready_execution
  end

  def test_table_name
    assert_equal "solid_queue_jobs", Sqdash::Models::Job.table_name
  end
end
