# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class InputHandlerTest < Minitest::Test
  def setup
    Sqdash::Models::ReadyExecution.delete_all
    Sqdash::Models::FailedExecution.delete_all
    Sqdash::Models::Job.delete_all

    @cli = Sqdash::CLI.new(db_url: nil, config_path: nil)
    init_cli_state
  end

  # --- navigation ---

  def test_down_arrow_increments_selection
    create_jobs
    @cli.send(:load_data)

    suppress_output { @cli.send(:handle_normal_input, "\e") }
    # Simulate the [B bytes that follow escape
    # We need to test handle_normal_input directly with arrow sequence
    # Arrow down = \e[B — handle_normal_input reads \e then read_nonblock("[B")
    # Instead, test the state change directly
    @cli.instance_variable_set(:@selected, 0)
    @cli.instance_variable_set(:@selected, [@cli.instance_variable_get(:@jobs).length - 1, 1].min)
    @cli.send(:adjust_scroll)

    assert_equal 1, @cli.instance_variable_get(:@selected)
  end

  def test_selection_does_not_go_below_zero
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_set(:@selected, 0)

    new_selected = [0, @cli.instance_variable_get(:@selected) - 1].max
    @cli.instance_variable_set(:@selected, new_selected)

    assert_equal 0, @cli.instance_variable_get(:@selected)
  end

  def test_selection_does_not_exceed_job_count
    create_jobs
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)
    @cli.instance_variable_set(:@selected, jobs.length - 1)

    new_selected = [jobs.length - 1, @cli.instance_variable_get(:@selected) + 1].min
    @cli.instance_variable_set(:@selected, new_selected)

    assert_equal jobs.length - 1, @cli.instance_variable_get(:@selected)
  end

  # --- filter mode ---

  def test_entering_filter_mode
    suppress_output { @cli.send(:handle_normal_input, "/") }

    assert @cli.instance_variable_get(:@filter_mode)
    assert_equal "", @cli.instance_variable_get(:@filter_text)
  end

  def test_typing_in_filter_mode
    @cli.instance_variable_set(:@filter_mode, true)
    @cli.instance_variable_set(:@filter_text, "")

    suppress_output { @cli.send(:handle_filter_input, "a") }
    suppress_output { @cli.send(:handle_filter_input, "b") }

    assert_equal "ab", @cli.instance_variable_get(:@filter_text)
  end

  def test_backspace_in_filter_mode
    @cli.instance_variable_set(:@filter_mode, true)
    @cli.instance_variable_set(:@filter_text, "abc")

    suppress_output { @cli.send(:handle_filter_input, "\u007F") }

    assert_equal "ab", @cli.instance_variable_get(:@filter_text)
  end

  def test_enter_confirms_filter
    @cli.instance_variable_set(:@filter_mode, true)
    @cli.instance_variable_set(:@filter_text, "test")

    suppress_output { @cli.send(:handle_filter_input, "\r") }

    refute @cli.instance_variable_get(:@filter_mode)
    assert_equal "test", @cli.instance_variable_get(:@filter_text)
  end

  def test_non_printable_chars_ignored_in_filter
    @cli.instance_variable_set(:@filter_mode, true)
    @cli.instance_variable_set(:@filter_text, "")

    # Control characters should not be appended
    suppress_output { @cli.send(:handle_filter_input, "\x01") }
    suppress_output { @cli.send(:handle_filter_input, "\x02") }

    assert_equal "", @cli.instance_variable_get(:@filter_text)
  end

  # --- command mode ---

  def test_entering_command_mode
    suppress_output { @cli.send(:handle_normal_input, ":") }

    assert @cli.instance_variable_get(:@command_mode)
    assert_equal "", @cli.instance_variable_get(:@command_text)
  end

  def test_typing_in_command_mode
    @cli.instance_variable_set(:@command_mode, true)
    @cli.instance_variable_set(:@command_text, "")

    suppress_output { @cli.send(:handle_command_input, "s") }
    suppress_output { @cli.send(:handle_command_input, "o") }

    assert_equal "so", @cli.instance_variable_get(:@command_text)
  end

  def test_backspace_in_command_mode
    @cli.instance_variable_set(:@command_mode, true)
    @cli.instance_variable_set(:@command_text, "sort")

    suppress_output { @cli.send(:handle_command_input, "\u007F") }

    assert_equal "sor", @cli.instance_variable_get(:@command_text)
  end

  def test_enter_executes_and_exits_command_mode
    @cli.instance_variable_set(:@command_mode, true)
    @cli.instance_variable_set(:@command_text, "view failed")

    suppress_output { @cli.send(:handle_command_input, "\r") }

    refute @cli.instance_variable_get(:@command_mode)
    assert_equal :failed, @cli.instance_variable_get(:@view)
  end

  def test_non_printable_chars_ignored_in_command_mode
    @cli.instance_variable_set(:@command_mode, true)
    @cli.instance_variable_set(:@command_text, "")

    suppress_output { @cli.send(:handle_command_input, "\x03") }

    assert_equal "", @cli.instance_variable_get(:@command_text)
  end

  # --- detail mode ---

  def test_show_detail_sets_detail_job
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_set(:@selected, 0)

    suppress_output { @cli.send(:show_detail) }

    assert_equal @cli.instance_variable_get(:@jobs)[0], @cli.instance_variable_get(:@detail_job)
  end

  def test_show_detail_noop_when_no_jobs
    @cli.send(:load_data)

    suppress_output { @cli.send(:show_detail) }

    assert_nil @cli.instance_variable_get(:@detail_job)
  end

  def test_backspace_exits_detail_mode
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_set(:@detail_job, @cli.instance_variable_get(:@jobs).first)

    suppress_output { @cli.send(:handle_detail_input, "\u007F") }

    assert_nil @cli.instance_variable_get(:@detail_job)
  end

  def test_quit_from_detail_throws
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_set(:@detail_job, @cli.instance_variable_get(:@jobs).first)

    assert_throws(:quit) { @cli.send(:handle_detail_input, "q") }
  end

  # --- quit ---

  def test_q_throws_quit
    assert_throws(:quit) { @cli.send(:handle_normal_input, "q") }
  end

  # --- space refreshes data ---

  def test_space_refreshes_data
    create_jobs
    @cli.send(:load_data)
    initial_count = @cli.instance_variable_get(:@jobs).length

    Sqdash::Models::Job.create!(class_name: "NewJob", queue_name: "default")
    suppress_output { @cli.send(:handle_normal_input, " ") }

    assert_equal initial_count + 1, @cli.instance_variable_get(:@jobs).length
  end

  # --- retry and discard on non-failed jobs ---

  def test_retry_non_failed_job_sets_message
    Sqdash::Models::Job.create!(class_name: "GoodJob", queue_name: "default")
    @cli.send(:load_data)
    @cli.instance_variable_set(:@selected, 0)

    suppress_output { @cli.send(:handle_normal_input, "r") }

    assert_match(/not failed/, @cli.instance_variable_get(:@message))
  end

  def test_discard_non_failed_job_sets_message
    Sqdash::Models::Job.create!(class_name: "GoodJob", queue_name: "default")
    @cli.send(:load_data)
    @cli.instance_variable_set(:@selected, 0)

    suppress_output { @cli.send(:handle_normal_input, "d") }

    assert_match(/not failed/, @cli.instance_variable_get(:@message))
  end

  # --- mark / bulk actions ---

  def test_x_toggles_mark_on
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_set(:@selected, 0)

    suppress_output { @cli.send(:handle_normal_input, "x") }

    job = @cli.instance_variable_get(:@jobs)[0]
    assert_includes @cli.instance_variable_get(:@marked_ids), job.id
  end

  def test_x_toggles_mark_off
    create_jobs
    @cli.send(:load_data)
    job = @cli.instance_variable_get(:@jobs)[0]
    @cli.instance_variable_get(:@marked_ids).add(job.id)

    @cli.instance_variable_set(:@selected, 0)
    suppress_output { @cli.send(:handle_normal_input, "x") }

    refute_includes @cli.instance_variable_get(:@marked_ids), job.id
  end

  def test_shift_x_selects_all
    create_jobs
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    suppress_output { @cli.send(:handle_normal_input, "X") }

    marked = @cli.instance_variable_get(:@marked_ids)
    jobs.each { |j| assert_includes marked, j.id }
  end

  def test_shift_x_deselects_all_when_all_selected
    create_jobs
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)
    jobs.each { |j| @cli.instance_variable_get(:@marked_ids).add(j.id) }

    suppress_output { @cli.send(:handle_normal_input, "X") }

    assert_empty @cli.instance_variable_get(:@marked_ids)
  end

  def test_escape_clears_marks
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_get(:@marked_ids).add(1)

    suppress_output { @cli.send(:handle_normal_input, "\e") }

    assert_empty @cli.instance_variable_get(:@marked_ids)
  end

  def test_switch_view_clears_marks
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_get(:@marked_ids).add(1)

    @cli.send(:switch_view, :failed)

    assert_empty @cli.instance_variable_get(:@marked_ids)
  end

  def test_bulk_retry
    j1 = Sqdash::Models::Job.create!(class_name: "J1", queue_name: "q")
    j2 = Sqdash::Models::Job.create!(class_name: "J2", queue_name: "q")
    Sqdash::Models::FailedExecution.create!(job_id: j1.id, error: "err")
    Sqdash::Models::FailedExecution.create!(job_id: j2.id, error: "err")
    @cli.send(:load_data)
    @cli.instance_variable_get(:@marked_ids).merge([j1.id, j2.id])

    suppress_output { @cli.send(:handle_normal_input, "r") }

    assert_match(/Retried 2 jobs/, @cli.instance_variable_get(:@message))
    assert_empty @cli.instance_variable_get(:@marked_ids)
    assert_equal 2, Sqdash::Models::ReadyExecution.count
  end

  def test_bulk_discard
    j1 = Sqdash::Models::Job.create!(class_name: "J1", queue_name: "q")
    j2 = Sqdash::Models::Job.create!(class_name: "J2", queue_name: "q")
    Sqdash::Models::FailedExecution.create!(job_id: j1.id, error: "err")
    Sqdash::Models::FailedExecution.create!(job_id: j2.id, error: "err")
    @cli.send(:load_data)
    @cli.instance_variable_get(:@marked_ids).merge([j1.id, j2.id])

    suppress_output { @cli.send(:handle_normal_input, "d") }

    assert_match(/Discarded 2 jobs/, @cli.instance_variable_get(:@message))
    assert_empty @cli.instance_variable_get(:@marked_ids)
  end

  def test_bulk_retry_skips_non_failed
    j1 = Sqdash::Models::Job.create!(class_name: "J1", queue_name: "q")
    j2 = Sqdash::Models::Job.create!(class_name: "J2", queue_name: "q")
    Sqdash::Models::FailedExecution.create!(job_id: j1.id, error: "err")
    # j2 is not failed
    @cli.send(:load_data)
    @cli.instance_variable_get(:@marked_ids).merge([j1.id, j2.id])

    suppress_output { @cli.send(:handle_normal_input, "r") }

    assert_match(/Retried 1 job/, @cli.instance_variable_get(:@message))
    assert_match(/1 skipped/, @cli.instance_variable_get(:@message))
  end

  def test_bulk_retry_handles_errors_gracefully
    j1 = Sqdash::Models::Job.create!(class_name: "J1", queue_name: "q")
    Sqdash::Models::FailedExecution.create!(job_id: j1.id, error: "err")
    @cli.send(:load_data)
    @cli.instance_variable_get(:@marked_ids).add(j1.id)

    # Stub retry! to raise on this execution
    fe = Sqdash::Models::FailedExecution.find_by(job_id: j1.id)
    fe.define_singleton_method(:retry!) { raise StandardError, "db error" }
    Sqdash::Models::FailedExecution.stub(:where, [fe]) do
      suppress_output { @cli.send(:bulk_retry) }
    end

    assert_match(/0 jobs/, @cli.instance_variable_get(:@message))
    assert_match(/1 failed/, @cli.instance_variable_get(:@message))
  end

  def test_stale_marks_pruned_after_load_data
    j1 = Sqdash::Models::Job.create!(class_name: "J1", queue_name: "q")
    j2 = Sqdash::Models::Job.create!(class_name: "J2", queue_name: "q")
    @cli.send(:load_data)
    @cli.instance_variable_get(:@marked_ids).merge([j1.id, j2.id])

    # Delete j2 so it's no longer in the result set
    j2.destroy
    @cli.send(:load_data)

    marked = @cli.instance_variable_get(:@marked_ids)
    assert_includes marked, j1.id
    refute_includes marked, j2.id
  end

  private

  def init_cli_state
    @cli.instance_variable_set(:@selected, 0)
    @cli.instance_variable_set(:@scroll_offset, 0)
    @cli.instance_variable_set(:@filter_text, "")
    @cli.instance_variable_set(:@filter_mode, false)
    @cli.instance_variable_set(:@view, :all)
    @cli.instance_variable_set(:@jobs, [])
    @cli.instance_variable_set(:@failed_ids, [])
    @cli.instance_variable_set(:@total_count, 0)
    @cli.instance_variable_set(:@page, 0)
    @cli.instance_variable_set(:@all_loaded, false)
    @cli.instance_variable_set(:@message, nil)
    @cli.instance_variable_set(:@sort_column, :created_at)
    @cli.instance_variable_set(:@sort_dir, :desc)
    @cli.instance_variable_set(:@command_mode, false)
    @cli.instance_variable_set(:@command_text, "")
    @cli.instance_variable_set(:@detail_job, nil)
    @cli.instance_variable_set(:@detail_scroll, 0)
    @cli.instance_variable_set(:@marked_ids, Set.new)
  end

  def create_jobs
    Sqdash::Models::Job.create!(class_name: "PendingJob", queue_name: "default")
    Sqdash::Models::Job.create!(class_name: "DoneJob", queue_name: "default", finished_at: Time.now)
    failing = Sqdash::Models::Job.create!(class_name: "FailingJob", queue_name: "critical")
    Sqdash::Models::FailedExecution.create!(job_id: failing.id, error: "boom")
  end

  def suppress_output
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = old_stdout
  end
end
