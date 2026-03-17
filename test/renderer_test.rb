# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class RendererTest < Minitest::Test
  def setup
    Sqdash::Models::ReadyExecution.delete_all
    Sqdash::Models::FailedExecution.delete_all
    Sqdash::Models::Job.delete_all

    @cli = Sqdash::CLI.new(db_url: nil, config_path: nil)
    init_cli_state
  end

  # --- draw_list_screen ---

  def test_draw_list_screen_with_no_jobs
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    assert_includes output, "sqdash"
    assert_includes output, "No jobs found"
    refute_includes output, "\x00"
  end

  def test_draw_list_screen_with_jobs
    create_jobs
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    assert_includes output, "PendingJob"
    assert_includes output, "DoneJob"
    assert_includes output, "FailingJob"
    assert_includes output, "Total:"
    assert_includes output, "Showing:"
  end

  def test_draw_list_screen_with_active_filter
    create_jobs
    @cli.instance_variable_set(:@filter_mode, true)
    @cli.instance_variable_set(:@filter_text, "Fail")
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    assert_includes output, "Fail"
    assert_includes output, "Tab"
  end

  def test_draw_list_screen_with_command_mode
    create_jobs
    @cli.instance_variable_set(:@command_mode, true)
    @cli.instance_variable_set(:@command_text, "sort")
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    assert_includes output, "sort"
    assert_includes output, "Enter"
  end

  def test_draw_list_screen_with_applied_filter
    create_jobs
    @cli.instance_variable_set(:@filter_text, "Pending")
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    assert_includes output, "Pending"
    assert_includes output, "Esc to clear"
  end

  def test_draw_list_screen_with_message
    create_jobs
    @cli.send(:load_data)
    @cli.instance_variable_set(:@message, "Retried job 1")
    output = capture_draw { @cli.send(:draw_list_screen) }

    assert_includes output, "Retried job 1"
  end

  def test_draw_list_screen_with_failed_view
    create_jobs
    @cli.instance_variable_set(:@view, :failed)
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    assert_includes output, "FAILED"
    assert_includes output, "FailingJob"
    refute_includes output, "PendingJob"
  end

  # --- draw_detail_screen ---

  def test_draw_detail_screen
    job = Sqdash::Models::Job.create!(
      class_name: "DetailJob", queue_name: "default",
      arguments: '{"key": "value"}', priority: 5
    )
    @cli.send(:load_data)
    @cli.instance_variable_set(:@detail_job, job)
    output = capture_draw { @cli.send(:draw_detail_screen) }

    assert_includes output, "DetailJob"
    assert_includes output, "default"
    assert_includes output, "key"
    assert_includes output, "value"
  end

  def test_draw_detail_screen_with_failed_job
    job = Sqdash::Models::Job.create!(class_name: "BadJob", queue_name: "default")
    Sqdash::Models::FailedExecution.create!(job_id: job.id, error: "RuntimeError: kaboom\n  app/jobs/bad_job.rb:10")
    @cli.send(:load_data)
    @cli.instance_variable_set(:@detail_job, job)
    output = capture_draw { @cli.send(:draw_detail_screen) }

    assert_includes output, "Error:"
    assert_includes output, "kaboom"
    assert_includes output, "bad_job.rb"
  end

  # --- truncate ---

  def test_truncate_short_string_unchanged
    result = @cli.send(:truncate, "hello", 10)
    assert_equal "hello", result
  end

  def test_truncate_long_string
    result = @cli.send(:truncate, "hello world this is long", 5)
    stripped = result.gsub(/\e\[[0-9;]*m/, "")
    assert_equal 5, stripped.length
  end

  def test_truncate_preserves_ansi_codes
    input = "\e[31mhello world\e[0m"
    result = @cli.send(:truncate, input, 5)
    assert_includes result, "\e[31m"
    assert_includes result, "\e[0m"
    stripped = result.gsub(/\e\[[0-9;]*m/, "")
    assert_equal 5, stripped.length
  end

  # --- output contains only valid ANSI sequences ---

  def test_output_contains_no_raw_control_chars
    create_jobs
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    # Strip valid ANSI escape sequences
    stripped = output.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
    # No raw escape, bell, or null bytes should remain
    refute_match(/[\x00\x07]/, stripped, "Output contains raw control characters")
  end

  def test_detail_output_contains_no_raw_control_chars
    job = Sqdash::Models::Job.create!(class_name: "TestJob", queue_name: "q", arguments: '["arg"]')
    @cli.send(:load_data)
    @cli.instance_variable_set(:@detail_job, job)
    output = capture_draw { @cli.send(:draw_detail_screen) }

    stripped = output.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
    refute_match(/[\x00\x07]/, stripped, "Detail output contains raw control characters")
  end

  # --- diagonal / line discipline ---

  def test_every_list_line_ends_with_clear_to_eol
    create_jobs
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    lines = output.split("\n")
    # Every line that has content should end with \e[K (clear to end of line)
    # or be a cursor positioning escape (like position info)
    content_lines = lines.reject { |l| l.strip.empty? }
    missing_clear = content_lines.reject { |l| l.include?("\e[K") || l.match?(/\e\[\d+;\d+H/) }
    assert_empty missing_clear, "Lines missing \\e[K clear: #{missing_clear.inspect}"
  end

  def test_every_detail_line_ends_with_clear_to_eol
    job = Sqdash::Models::Job.create!(class_name: "TestJob", queue_name: "q", arguments: '["a"]')
    @cli.send(:load_data)
    @cli.instance_variable_set(:@detail_job, job)
    output = capture_draw { @cli.send(:draw_detail_screen) }

    lines = output.split("\n")
    content_lines = lines.reject { |l| l.strip.empty? }
    missing_clear = content_lines.reject { |l| l.include?("\e[K") || l.match?(/\e\[\d+;\d+H/) }
    assert_empty missing_clear, "Detail lines missing \\e[K clear: #{missing_clear.inspect}"
  end

  def test_no_visible_line_exceeds_terminal_width
    create_jobs
    @cli.send(:load_data)
    output = capture_draw { @cli.send(:draw_list_screen) }

    width = @cli.send(:terminal_width)
    lines = output.split("\n")
    lines.each do |line|
      visible = line.gsub(/\e\[[0-9;]*[A-Za-z]/, "")
      assert visible.length <= width + 1,
             "Line exceeds terminal width (#{visible.length} > #{width}): #{visible[0..80]}..."
    end
  end

  # --- column_widths ---

  def test_column_widths_sum_fits_terminal
    cols = @cli.send(:column_widths)
    total = 2 + cols[:id] + cols[:job] + cols[:queue] + cols[:status] + cols[:created]
    assert total <= @cli.send(:terminal_width) + 2
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
  end

  def create_jobs
    Sqdash::Models::Job.create!(class_name: "PendingJob", queue_name: "default")
    Sqdash::Models::Job.create!(class_name: "DoneJob", queue_name: "default", finished_at: Time.now)
    failing = Sqdash::Models::Job.create!(class_name: "FailingJob", queue_name: "critical")
    Sqdash::Models::FailedExecution.create!(job_id: failing.id, error: "boom")
  end

  def capture_draw
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
