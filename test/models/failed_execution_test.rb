# frozen_string_literal: true

require_relative "../test_helper"

class FailedExecutionTest < Minitest::Test
  def setup
    Sqdash::Models::ReadyExecution.delete_all
    Sqdash::Models::FailedExecution.delete_all
    Sqdash::Models::Job.delete_all

    @job = Sqdash::Models::Job.create!(
      class_name: "TestJob",
      queue_name: "default",
      priority: 0
    )
    @failed = Sqdash::Models::FailedExecution.create!(
      job_id: @job.id,
      error: "RuntimeError: something broke"
    )
  end

  # --- retry! ---

  def test_retry_creates_ready_execution
    @failed.retry!

    ready = Sqdash::Models::ReadyExecution.find_by(job_id: @job.id)
    assert ready, "Expected a ReadyExecution to be created"
    assert_equal @job.queue_name, ready.queue_name
    assert_equal @job.priority, ready.priority
  end

  def test_retry_destroys_failed_execution
    @failed.retry!

    assert_nil Sqdash::Models::FailedExecution.find_by(id: @failed.id)
  end

  def test_retry_is_transactional
    # Sabotage ReadyExecution creation to trigger a rollback
    Sqdash::Models::ReadyExecution.stub(:create!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      assert_raises(ActiveRecord::RecordInvalid) { @failed.retry! }
    end

    # FailedExecution should still exist (rolled back)
    assert Sqdash::Models::FailedExecution.exists?(@failed.id)
  end

  # --- discard! ---

  def test_discard_sets_finished_at_on_job
    @failed.discard!

    @job.reload
    assert @job.finished_at, "Expected job.finished_at to be set"
  end

  def test_discard_destroys_failed_execution
    @failed.discard!

    assert_nil Sqdash::Models::FailedExecution.find_by(id: @failed.id)
  end

  def test_discard_is_transactional
    # Sabotage job update to trigger a rollback
    @job.stub(:update!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      @failed.stub(:job, @job) do
        assert_raises(ActiveRecord::RecordInvalid) { @failed.discard! }
      end
    end

    # FailedExecution should still exist (rolled back)
    assert Sqdash::Models::FailedExecution.exists?(@failed.id)
  end

  # --- association ---

  def test_belongs_to_job
    assert_equal @job, @failed.job
  end
end
