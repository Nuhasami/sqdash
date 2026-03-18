# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  def setup
    Sqdash::Models::ReadyExecution.delete_all
    Sqdash::Models::FailedExecution.delete_all
    Sqdash::Models::Job.delete_all

    @cli = Sqdash::CLI.new(db_url: nil, config_path: nil)
    init_cli_state
  end

  # --- view filtering ---

  def test_view_all_returns_all_jobs
    create_jobs

    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 3, jobs.length
  end

  def test_view_failed_returns_only_failed_jobs
    create_jobs

    @cli.instance_variable_set(:@view, :failed)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 1, jobs.length
    assert_equal "FailingJob", jobs.first.class_name
  end

  def test_view_completed_returns_only_completed_jobs
    create_jobs

    @cli.instance_variable_set(:@view, :completed)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 1, jobs.length
    assert_equal "DoneJob", jobs.first.class_name
  end

  def test_view_pending_returns_only_pending_jobs
    create_jobs

    @cli.instance_variable_set(:@view, :pending)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 1, jobs.length
    assert_equal "PendingJob", jobs.first.class_name
  end

  def test_view_failed_with_no_failures_returns_empty
    Sqdash::Models::Job.create!(class_name: "PendingJob", queue_name: "default")

    @cli.instance_variable_set(:@view, :failed)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_empty jobs
  end

  # --- text filtering ---

  def test_filter_by_class_name
    create_jobs

    @cli.instance_variable_set(:@filter_text, "Failing")
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 1, jobs.length
    assert_equal "FailingJob", jobs.first.class_name
  end

  def test_filter_by_queue_name
    Sqdash::Models::Job.create!(class_name: "JobA", queue_name: "mailers")
    Sqdash::Models::Job.create!(class_name: "JobB", queue_name: "default")

    @cli.instance_variable_set(:@filter_text, "mailer")
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 1, jobs.length
    assert_equal "mailers", jobs.first.queue_name
  end

  def test_filter_by_id
    job = Sqdash::Models::Job.create!(class_name: "JobA", queue_name: "default")
    Sqdash::Models::Job.create!(class_name: "JobB", queue_name: "default")

    @cli.instance_variable_set(:@filter_text, job.id.to_s)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_includes jobs.map(&:id), job.id
  end

  def test_filter_is_case_insensitive
    Sqdash::Models::Job.create!(class_name: "MySpecialJob", queue_name: "default")
    Sqdash::Models::Job.create!(class_name: "OtherJob", queue_name: "default")

    @cli.instance_variable_set(:@filter_text, "myspecial")
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 1, jobs.length
    assert_equal "MySpecialJob", jobs.first.class_name
  end

  def test_filter_with_no_matches_returns_empty
    Sqdash::Models::Job.create!(class_name: "TestJob", queue_name: "default")

    @cli.instance_variable_set(:@filter_text, "zzz_nonexistent")
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_empty jobs
  end

  def test_combined_view_and_text_filter
    create_jobs

    @cli.instance_variable_set(:@view, :pending)
    @cli.instance_variable_set(:@filter_text, "Pending")
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal 1, jobs.length
    assert_equal "PendingJob", jobs.first.class_name
  end

  # --- sorting ---

  def test_sort_by_created_at_desc
    j1 = Sqdash::Models::Job.create!(class_name: "OldJob", queue_name: "default", created_at: 2.days.ago)
    j2 = Sqdash::Models::Job.create!(class_name: "NewJob", queue_name: "default", created_at: 1.minute.ago)

    @cli.instance_variable_set(:@sort_column, :created_at)
    @cli.instance_variable_set(:@sort_dir, :desc)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal j2.id, jobs.first.id
    assert_equal j1.id, jobs.last.id
  end

  def test_sort_by_created_at_asc
    j1 = Sqdash::Models::Job.create!(class_name: "OldJob", queue_name: "default", created_at: 2.days.ago)
    j2 = Sqdash::Models::Job.create!(class_name: "NewJob", queue_name: "default", created_at: 1.minute.ago)

    @cli.instance_variable_set(:@sort_column, :created_at)
    @cli.instance_variable_set(:@sort_dir, :asc)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal j1.id, jobs.first.id
    assert_equal j2.id, jobs.last.id
  end

  def test_sort_by_id_desc
    j1 = Sqdash::Models::Job.create!(class_name: "JobA", queue_name: "default")
    j2 = Sqdash::Models::Job.create!(class_name: "JobB", queue_name: "default")

    @cli.instance_variable_set(:@sort_column, :id)
    @cli.instance_variable_set(:@sort_dir, :desc)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal j2.id, jobs.first.id
    assert_equal j1.id, jobs.last.id
  end

  def test_sort_by_id_asc
    j1 = Sqdash::Models::Job.create!(class_name: "JobA", queue_name: "default")
    j2 = Sqdash::Models::Job.create!(class_name: "JobB", queue_name: "default")

    @cli.instance_variable_set(:@sort_column, :id)
    @cli.instance_variable_set(:@sort_dir, :asc)
    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)

    assert_equal j1.id, jobs.first.id
    assert_equal j2.id, jobs.last.id
  end

  # --- execute_command ---

  def test_execute_sort_command
    @cli.instance_variable_set(:@command_text, "sort id asc")
    @cli.send(:execute_command)

    assert_equal :id, @cli.instance_variable_get(:@sort_column)
    assert_equal :asc, @cli.instance_variable_get(:@sort_dir)
  end

  def test_execute_sort_command_defaults
    @cli.instance_variable_set(:@command_text, "sort")
    @cli.send(:execute_command)

    assert_equal :created_at, @cli.instance_variable_get(:@sort_column)
    assert_equal :desc, @cli.instance_variable_get(:@sort_dir)
  end

  def test_execute_sort_unknown_field_sets_message
    @cli.instance_variable_set(:@command_text, "sort banana")
    @cli.send(:execute_command)

    assert_match(/Unknown sort field/, @cli.instance_variable_get(:@message))
  end

  def test_execute_sort_unknown_direction_sets_message
    @cli.instance_variable_set(:@command_text, "sort created sideways")
    @cli.send(:execute_command)

    assert_match(/Unknown sort direction/, @cli.instance_variable_get(:@message))
  end

  def test_execute_view_command
    @cli.instance_variable_set(:@command_text, "view failed")
    @cli.send(:execute_command)

    assert_equal :failed, @cli.instance_variable_get(:@view)
  end

  def test_execute_view_command_defaults_to_all
    @cli.instance_variable_set(:@command_text, "view")
    @cli.send(:execute_command)

    assert_equal :all, @cli.instance_variable_get(:@view)
  end

  def test_execute_unknown_command_sets_message
    @cli.instance_variable_set(:@command_text, "explode")
    @cli.send(:execute_command)

    assert_match(/Unknown command/, @cli.instance_variable_get(:@message))
  end

  def test_execute_empty_command_does_nothing
    @cli.instance_variable_set(:@command_text, "   ")
    @cli.send(:execute_command)

    assert_nil @cli.instance_variable_get(:@message)
  end

  # --- job_status ---

  def test_job_status_failed
    job = Sqdash::Models::Job.create!(class_name: "J", queue_name: "q")
    Sqdash::Models::FailedExecution.create!(job_id: job.id, error: "err")

    @cli.instance_variable_set(:@failed_ids, [job.id])
    assert_equal :failed, @cli.send(:job_status, job)
  end

  def test_job_status_completed
    job = Sqdash::Models::Job.create!(class_name: "J", queue_name: "q", finished_at: Time.now)

    @cli.instance_variable_set(:@failed_ids, [])
    assert_equal :completed, @cli.send(:job_status, job)
  end

  def test_job_status_pending
    job = Sqdash::Models::Job.create!(class_name: "J", queue_name: "q")

    @cli.instance_variable_set(:@failed_ids, [])
    assert_equal :pending, @cli.send(:job_status, job)
  end

  # --- --help and --version flags ---

  def test_help_flag_prints_help_and_exits
    original_argv = ARGV.dup
    ARGV.replace(["--help"])
    out, = capture_io do
      assert_raises(SystemExit) { Sqdash::CLI.start }
    end
    assert_includes out, "Usage: sqdash"
    assert_includes out, "Keybindings:"
  ensure
    ARGV.replace(original_argv)
  end

  def test_version_flag_prints_version_and_exits
    original_argv = ARGV.dup
    ARGV.replace(["--version"])
    out, = capture_io do
      assert_raises(SystemExit) { Sqdash::CLI.start }
    end
    assert_includes out, "sqdash #{Sqdash::VERSION}"
  ensure
    ARGV.replace(original_argv)
  end

  # --- build_detail_lines edge cases ---

  def test_detail_lines_with_nil_arguments
    job = Sqdash::Models::Job.create!(class_name: "NilJob", queue_name: "default", arguments: nil)
    @cli.instance_variable_set(:@failed_ids, [])
    lines = @cli.send(:build_detail_lines, job)

    args_index = lines.index { |l| l.include?("Arguments:") }
    assert_equal "  —", lines[args_index + 1]
  end

  def test_detail_lines_with_empty_arguments
    job = Sqdash::Models::Job.create!(class_name: "EmptyJob", queue_name: "default", arguments: "")
    @cli.instance_variable_set(:@failed_ids, [])
    lines = @cli.send(:build_detail_lines, job)

    args_index = lines.index { |l| l.include?("Arguments:") }
    assert_equal "  —", lines[args_index + 1]
  end

  def test_detail_lines_with_valid_json_arguments
    job = Sqdash::Models::Job.create!(class_name: "JsonJob", queue_name: "default", arguments: '["hello"]')
    @cli.instance_variable_set(:@failed_ids, [])
    lines = @cli.send(:build_detail_lines, job)

    args_index = lines.index { |l| l.include?("Arguments:") }
    args_lines = lines[(args_index + 1)..].take_while { |l| !l.include?("\e[1m") && !l.empty? }
    assert(args_lines.any? { |l| l.include?("hello") })
  end

  def test_detail_lines_with_invalid_json_arguments
    job = Sqdash::Models::Job.create!(class_name: "BadJob", queue_name: "default", arguments: "not json{{{")
    @cli.instance_variable_set(:@failed_ids, [])
    lines = @cli.send(:build_detail_lines, job)

    args_index = lines.index { |l| l.include?("Arguments:") }
    assert_equal "  not json{{{", lines[args_index + 1]
  end

  # --- pagination ---

  def test_load_data_respects_page_size
    # Create more jobs than PAGE_SIZE
    (Sqdash::CLI::PAGE_SIZE + 10).times do |i|
      Sqdash::Models::Job.create!(class_name: "Job#{i}", queue_name: "default")
    end

    @cli.send(:load_data)
    jobs = @cli.instance_variable_get(:@jobs)
    total = @cli.instance_variable_get(:@total_count)

    assert_equal Sqdash::CLI::PAGE_SIZE, jobs.length
    assert_equal Sqdash::CLI::PAGE_SIZE + 10, total
    refute @cli.instance_variable_get(:@all_loaded)
  end

  def test_load_data_marks_all_loaded_when_under_page_size
    3.times { |i| Sqdash::Models::Job.create!(class_name: "Job#{i}", queue_name: "default") }

    @cli.send(:load_data)

    assert @cli.instance_variable_get(:@all_loaded)
    assert_equal 3, @cli.instance_variable_get(:@total_count)
  end

  def test_load_more_fetches_next_page
    (Sqdash::CLI::PAGE_SIZE + 10).times do |i|
      Sqdash::Models::Job.create!(class_name: "Job#{i}", queue_name: "default")
    end

    @cli.send(:load_data)
    assert_equal Sqdash::CLI::PAGE_SIZE, @cli.instance_variable_get(:@jobs).length

    @cli.send(:load_more)
    assert_equal Sqdash::CLI::PAGE_SIZE + 10, @cli.instance_variable_get(:@jobs).length
    assert @cli.instance_variable_get(:@all_loaded)
  end

  def test_load_more_noop_when_all_loaded
    3.times { |i| Sqdash::Models::Job.create!(class_name: "Job#{i}", queue_name: "default") }

    @cli.send(:load_data)
    assert @cli.instance_variable_get(:@all_loaded)

    @cli.send(:load_more)
    assert_equal 3, @cli.instance_variable_get(:@jobs).length
  end

  def test_total_count_with_view_filter
    Sqdash::Models::Job.create!(class_name: "PendingJob", queue_name: "default")
    Sqdash::Models::Job.create!(class_name: "DoneJob", queue_name: "default", finished_at: Time.now)

    @cli.instance_variable_set(:@view, :pending)
    @cli.send(:load_data)

    assert_equal 1, @cli.instance_variable_get(:@total_count)
  end

  def test_total_count_with_text_filter
    Sqdash::Models::Job.create!(class_name: "SpecialJob", queue_name: "default")
    Sqdash::Models::Job.create!(class_name: "OtherJob", queue_name: "default")

    @cli.instance_variable_set(:@filter_text, "Special")
    @cli.send(:load_data)

    assert_equal 1, @cli.instance_variable_get(:@total_count)
  end

  # --- selection clamping ---

  def test_selection_clamped_after_filter_reduces_list
    Sqdash::Models::Job.create!(class_name: "JobA", queue_name: "default")
    Sqdash::Models::Job.create!(class_name: "JobB", queue_name: "default")

    @cli.instance_variable_set(:@selected, 1)
    @cli.instance_variable_set(:@filter_text, "JobA")
    @cli.send(:load_data)

    assert_equal 0, @cli.instance_variable_get(:@selected)
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
end
