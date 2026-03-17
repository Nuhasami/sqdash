# frozen_string_literal: true

require "json"

module Sqdash
  module Renderer
    STATUS_TEXT = {
      failed: "\e[31m● failed\e[0m   ",
      completed: "\e[32m● completed\e[0m",
      pending: "\e[33m● pending\e[0m  "
    }.freeze

    VIEW_LABEL = {
      all: "ALL",
      failed: "\e[31mFAILED\e[0m",
      completed: "\e[32mCOMPLETED\e[0m",
      pending: "\e[33mPENDING\e[0m"
    }.freeze

    def truncate(str, max)
      return str if str.length <= max

      visible = str.gsub(/\e\[[0-9;]*m/, "")
      return str if visible.length <= max

      result = +""
      visible_count = 0
      i = 0
      while i < str.length && visible_count < max
        if str[i] == "\e" && str[i..] =~ /\A(\e\[[0-9;]*m)/
          result << ::Regexp.last_match(1)
          i += ::Regexp.last_match(1).length
        else
          result << str[i]
          visible_count += 1
          i += 1
        end
      end
      result << "\e[0m"
    end

    def terminal_height
      $stdout.winsize[0]
    rescue StandardError
      24
    end

    def terminal_width
      $stdout.winsize[1]
    rescue StandardError
      80
    end

    def visible_rows
      [terminal_height - 11, 5].max
    end

    def status_text(status)
      STATUS_TEXT[status]
    end

    def view_label
      VIEW_LABEL[@view]
    end

    def full_draw
      print "\e[?25l"
      print "\e[2J\e[H"
      draw_screen
    end

    def cleanup
      print "\e[?25h"
      print "\e[2J\e[H"
      puts "Goodbye!"
    end

    def column_widths
      w = terminal_width
      remaining = [w - 36, 10].max
      job_w = [remaining * 65 / 100, 6].max
      queue_w = [remaining - job_w, 4].max
      { id: 8, job: job_w, queue: queue_w, status: 14, created: 12 }
    end

    def draw_screen
      if @detail_job
        draw_detail_screen
      else
        draw_list_screen
      end
    end

    def draw_list_screen
      print "\e[H"
      w = terminal_width
      rows = visible_rows
      cols = column_widths

      # Header
      puts truncate("\e[1;36m sqdash \e[0m\e[36m Solid Queue Dashboard v#{Sqdash::VERSION}\e[0m", w) + "\e[K"
      puts "\e[90m#{'─' * w}\e[0m"

      # Stats bar
      total = Models::Job.count
      completed = Models::Job.where.not(finished_at: nil).count
      failed = @failed_ids.length
      pending = Models::ReadyExecution.count
      sort_label = "#{@sort_column == :id ? 'ID' : 'Created'} #{@sort_dir == :asc ? '↑' : '↓'}"
      stats = " \e[1mTotal:\e[0m #{total}  \e[32m✓ #{completed}\e[0m  \e[31m✗ #{failed}\e[0m  \e[33m◌ #{pending}\e[0m  │  View: #{view_label}  │  Sort: #{sort_label}  │  Showing: #{@jobs.length}"
      puts truncate(stats, w) + "\e[K"

      # Filter / Command bar
      if @command_mode
        print "\e[?25h"
        hint = command_autocomplete_hint
        puts truncate(
          " \e[1;35m:\e[0m #{@command_text}\e[90m#{hint}\e[0m  \e[90m<Tab> complete  <Enter> run  <Esc> cancel\e[0m", w
        ) + "\e[K"
      elsif @filter_mode
        print "\e[?25h"
        hint = autocomplete_hint
        puts truncate(" \e[1;33m/\e[0m #{@filter_text}\e[90m#{hint}\e[0m  \e[90m<Tab> complete  <Esc> cancel\e[0m",
                      w) + "\e[K"
      elsif @filter_text.length.positive?
        puts truncate(" \e[33m/#{@filter_text}\e[0m  \e[90m(/ to edit, Esc to clear)\e[0m", w) + "\e[K"
      else
        puts "\e[K"
      end

      puts "\e[90m#{'─' * w}\e[0m"

      # Column headers
      puts truncate(
        "\e[1m  #{'ID'.ljust(cols[:id])}#{'Job'.ljust(cols[:job])}#{'Queue'.ljust(cols[:queue])}#{'Status'.ljust(cols[:status])}Created\e[0m", w
      ) + "\e[K"

      # Job list
      visible_jobs = @jobs[@scroll_offset, rows] || []

      visible_jobs.each_with_index do |job, i|
        actual_index = @scroll_offset + i
        status = job_status(job)
        is_selected = actual_index == @selected
        created = job.created_at&.strftime("%m/%d %H:%M") || "—"

        line = "#{job.id.to_s.ljust(cols[:id])}#{job.class_name[0, cols[:job] - 1].ljust(cols[:job])}#{job.queue_name[0, cols[:queue] - 1].ljust(cols[:queue])}#{status_text(status)}  #{created}"

        if is_selected
          puts truncate("\e[7m▸ #{line}\e[0m", w) + "\e[K"
        else
          puts truncate("  #{line}", w) + "\e[K"
        end
      end

      # Empty state
      if visible_jobs.empty?
        puts "  \e[90mNo jobs found\e[0m\e[K"
        (rows - 1).times { puts "\e[K" }
      else
        (rows - visible_jobs.length).times { puts "\e[K" }
      end

      # Scrollbar hint
      puts "\e[90m#{'─' * w}\e[0m"

      # Message or footer
      if @message
        puts " \e[1;32m#{@message}\e[0m\e[K"
        @message = nil
      else
        puts truncate(" \e[90m↑↓ Navigate  Enter Detail  /Filter  :Command  r Retry  d Discard  q Quit\e[0m",
                      w) + "\e[K"
      end

      # Position info
      return unless @jobs.length.positive?

      pos = "#{@selected + 1}/#{@jobs.length}"
      print "\e[#{terminal_height};#{w - pos.length}H\e[90m#{pos}\e[0m"
    end

    def draw_detail_screen
      print "\e[H"
      w = terminal_width
      rows = terminal_height

      # Header
      puts truncate("\e[1;36m sqdash \e[0m\e[36m Job ##{@detail_job.id}\e[0m", w) + "\e[K"
      puts "\e[90m#{'─' * w}\e[0m"

      # Content area
      content_rows = rows - 4
      lines = build_detail_lines(@detail_job)

      # Clamp scroll
      max_scroll = [lines.length - content_rows, 0].max
      @detail_scroll = @detail_scroll.clamp(0, max_scroll)

      visible = lines[@detail_scroll, content_rows] || []
      visible.each { |line| puts truncate("  #{line}", w) + "\e[K" }

      (content_rows - visible.length).times { puts "\e[K" }

      puts "\e[90m#{'─' * w}\e[0m"

      if @message
        puts " \e[1;32m#{@message}\e[0m\e[K"
        @message = nil
      else
        puts truncate(" \e[90mEsc Back  ↑↓ Scroll  r Retry  d Discard  q Quit\e[0m", w) + "\e[K"
      end
    end

    def build_detail_lines(job)
      lines = []

      lines << "\e[1mClass:\e[0m       #{job.class_name}"
      lines << "\e[1mQueue:\e[0m       #{job.queue_name}"
      lines << "\e[1mPriority:\e[0m    #{job.priority || '—'}"
      lines << "\e[1mActive Job:\e[0m  #{job.active_job_id || '—'}"
      lines << ""

      status = job_status(job)
      lines << "\e[1mStatus:\e[0m      #{status_text(status)}"
      lines << ""

      lines << "\e[1mCreated:\e[0m     #{job.created_at || '—'}"
      lines << "\e[1mScheduled:\e[0m   #{job.scheduled_at || '—'}"
      lines << "\e[1mFinished:\e[0m    #{job.finished_at || '—'}"
      lines << ""

      lines << "\e[1mArguments:\e[0m"
      if job.arguments.nil? || job.arguments.empty?
        lines << "  —"
      else
        begin
          args = JSON.parse(job.arguments)
          JSON.pretty_generate(args).each_line { |l| lines << "  #{l.chomp}" }
        rescue JSON::ParserError, TypeError
          lines << "  #{job.arguments}"
        end
      end

      if status == :failed && job.failed_execution
        lines << ""
        lines << "\e[1;31mError:\e[0m"
        error_text = job.failed_execution.error || "No error message"
        error_text.each_line { |l| lines << "  #{l.chomp}" }
      end

      lines
    end
  end
end
