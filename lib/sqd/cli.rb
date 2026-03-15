# frozen_string_literal: true

require "io/console"

module Sqd
  class CLI
    DEFAULT_DB_URL = "postgres://sqd:sqd@localhost:5432/sqd_web_development_queue"

    COMMANDS = {
      "sort" => {
        "created" => ["asc", "desc"],
        "id" => ["asc", "desc"]
      },
      "view" => {
        "all" => [],
        "failed" => [],
        "completed" => [],
        "pending" => []
      }
    }.freeze

    def self.start
      new.run
    end

    def run
      Database.connect!(resolve_db_url)
      @selected = 0
      @scroll_offset = 0
      @filter_text = ""
      @filter_mode = false
      @view = :all  # :all, :failed, :completed, :pending
      @jobs = []
      @failed_ids = []
      @message = nil
      @sort_column = :created_at
      @sort_dir = :desc
      @command_mode = false
      @command_text = ""
      trap_resize
      load_data
      full_draw
      catch(:quit) { handle_input }
    ensure
      Signal.trap("WINCH", "DEFAULT")
      cleanup
    end

    private

    def resolve_db_url
      ARGV[0] || ENV["DATABASE_URL"] || DEFAULT_DB_URL
    end

    def cleanup
      print "\e[?25h"
      print "\e[2J\e[H"
      puts "Goodbye!"
    end

    def trap_resize
      Signal.trap("WINCH") do
        @needs_redraw = true
      end
    end

    def truncate(str, max)
      return str if str.length <= max

      # Strip ANSI codes to measure visible length
      visible = str.gsub(/\e\[[0-9;]*m/, "")
      return str if visible.length <= max

      # Truncate by walking through the string, tracking visible chars
      result = +""
      visible_count = 0
      i = 0
      while i < str.length && visible_count < max
        if str[i] == "\e" && str[i..] =~ /\A(\e\[[0-9;]*m)/
          result << $1
          i += $1.length
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
    end

    def terminal_width
      $stdout.winsize[1]
    end

    def visible_rows
      [terminal_height - 11, 5].max
    end

    def load_data
      @failed_ids = Models::FailedExecution.pluck(:job_id)

      scope = Models::Job.order(@sort_column => @sort_dir)

      # View filter
      case @view
      when :failed
        scope = @failed_ids.any? ? scope.where(id: @failed_ids) : scope.none
      when :completed
        scope = scope.where.not(finished_at: nil).where.not(id: @failed_ids)
      when :pending
        scope = scope.where(finished_at: nil).where.not(id: @failed_ids)
      end

      @jobs = scope.to_a

      # Text filter (k9s style — filters across all visible columns)
      if @filter_text.length > 0
        query = @filter_text.downcase
        @jobs = @jobs.select do |job|
          job.class_name.downcase.include?(query) ||
            job.queue_name.downcase.include?(query) ||
            job.id.to_s.include?(query)
        end
      end

      # Clamp selection
      @selected = [[@selected, @jobs.length - 1].min, 0].max
      adjust_scroll
    end

    def adjust_scroll
      if @selected < @scroll_offset
        @scroll_offset = @selected
      elsif @selected >= @scroll_offset + visible_rows
        @scroll_offset = @selected - visible_rows + 1
      end
    end

    def job_status(job)
      if @failed_ids.include?(job.id)
        :failed
      elsif job.finished_at
        :completed
      else
        :pending
      end
    end

    def status_text(status)
      case status
      when :failed    then "\e[31m● failed\e[0m   "
      when :completed then "\e[32m● completed\e[0m"
      when :pending   then "\e[33m● pending\e[0m  "
      end
    end

    def view_label
      case @view
      when :all       then "ALL"
      when :failed    then "\e[31mFAILED\e[0m"
      when :completed then "\e[32mCOMPLETED\e[0m"
      when :pending   then "\e[33mPENDING\e[0m"
      end
    end

    def full_draw
      print "\e[?25l"
      print "\e[2J\e[H"
      draw_screen
    end

    def column_widths
      w = terminal_width
      # Fixed columns: prefix(2) + ID(8) + Status(14) + Created(12) = 36
      remaining = [w - 36, 10].max
      # Job gets 65% of remaining, Queue gets 35%
      job_w = [remaining * 65 / 100, 6].max
      queue_w = [remaining - job_w, 4].max
      { id: 8, job: job_w, queue: queue_w, status: 14, created: 12 }
    end

    def draw_screen
      print "\e[H" # cursor home, no clear
      w = terminal_width
      rows = visible_rows
      cols = column_widths

      # Header
      puts truncate("\e[1;36m sqd \e[0m\e[36m Solid Queue Dashboard v#{Sqd::VERSION}\e[0m", w) + "\e[K"
      puts "\e[90m#{"─" * w}\e[0m"

      # Stats bar
      total = Models::Job.count
      completed = Models::Job.where.not(finished_at: nil).count
      failed = @failed_ids.length
      pending = Models::ReadyExecution.count
      sort_label = "#{@sort_column == :id ? "ID" : "Created"} #{@sort_dir == :asc ? "↑" : "↓"}"
      stats = " \e[1mTotal:\e[0m #{total}  \e[32m✓ #{completed}\e[0m  \e[31m✗ #{failed}\e[0m  \e[33m◌ #{pending}\e[0m  │  View: #{view_label}  │  Sort: #{sort_label}  │  Showing: #{@jobs.length}"
      puts truncate(stats, w) + "\e[K"

      # Filter / Command bar
      if @command_mode
        print "\e[?25h"
        hint = command_autocomplete_hint
        puts truncate(" \e[1;35m:\e[0m #{@command_text}\e[90m#{hint}\e[0m  \e[90m<Tab> complete  <Enter> run  <Esc> cancel\e[0m", w) + "\e[K"
      elsif @filter_mode
        print "\e[?25h" # show cursor in filter mode
        hint = autocomplete_hint
        puts truncate(" \e[1;33m/\e[0m #{@filter_text}\e[90m#{hint}\e[0m  \e[90m<Tab> complete  <Esc> cancel\e[0m", w) + "\e[K"
      elsif @filter_text.length > 0
        puts truncate(" \e[33m/#{@filter_text}\e[0m  \e[90m(/ to edit, Esc to clear)\e[0m", w) + "\e[K"
      else
        puts "\e[K"
      end

      puts "\e[90m#{"─" * w}\e[0m"

      # Column headers
      puts truncate("\e[1m  #{"ID".ljust(cols[:id])}#{"Job".ljust(cols[:job])}#{"Queue".ljust(cols[:queue])}#{"Status".ljust(cols[:status])}Created\e[0m", w) + "\e[K"

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

      # Clear remaining rows
      (rows - visible_jobs.length).times { puts "\e[K" }

      # Scrollbar hint
      puts "\e[90m#{"─" * w}\e[0m"

      # Message or footer
      if @message
        puts " \e[1;32m#{@message}\e[0m\e[K"
        @message = nil
      else
        puts truncate(" \e[90m↑↓ Navigate  /Filter  :Command  r Retry  d Discard  q Quit\e[0m", w) + "\e[K"
      end

      # Position info
      if @jobs.length > 0
        pos = "#{@selected + 1}/#{@jobs.length}"
        print "\e[#{terminal_height};#{w - pos.length}H\e[90m#{pos}\e[0m"
      end
    end

    def handle_input
      @saved_stty = `stty -g`.chomp
      system("stty", "-echo", "-icanon", "min", "1")
      loop do
        if @needs_redraw
          @needs_redraw = false
          adjust_scroll
          full_draw
        end

        key = read_key

        unless key
          # No input — auto-refresh data on idle
          load_data
          draw_screen
          next
        end

        if @command_mode
          handle_command_input(key)
        elsif @filter_mode
          handle_filter_input(key)
        else
          handle_normal_input(key)
        end

        draw_screen
      end
    ensure
      system("stty", @saved_stty) if @saved_stty
    end

    def read_key
      ready = IO.select([$stdin], nil, nil, 1)
      return nil unless ready

      $stdin.getc
    end

    def handle_filter_input(key)
      case key
      when "\r", "\n" # Enter — confirm filter
        @filter_mode = false
        print "\e[?25l"
        load_data
      when "\e" # Escape — cancel filter (drain arrow key bytes)
        $stdin.read_nonblock(2) rescue nil
        @filter_mode = false
        @filter_text = ""
        print "\e[?25l"
        load_data
      when "\t" # Tab — autocomplete
        autocomplete_filter
      when "\u007F", "\b" # Backspace
        @filter_text = @filter_text[0..-2]
        load_data
      else
        if key.match?(/[[:print:]]/)
          @filter_text += key
          load_data
        end
      end
    end

    def autocomplete_filter
      return if @filter_text.empty?

      query = @filter_text.downcase

      # Collect all completable values
      candidates = (
        Models::Job.distinct.pluck(:class_name) +
        Models::Job.distinct.pluck(:queue_name)
      ).uniq

      matches = candidates.select { |c| c.downcase.start_with?(query) }

      if matches.length == 1
        # Exact single match — complete it
        @filter_text = matches.first
      elsif matches.length > 1
        # Multiple matches — complete to common prefix
        @filter_text = common_prefix(matches)
      end

      load_data
    end

    def autocomplete_hint
      return "" if @filter_text.empty?

      query = @filter_text.downcase
      candidates = (
        Models::Job.distinct.pluck(:class_name) +
        Models::Job.distinct.pluck(:queue_name)
      ).uniq

      matches = candidates.select { |c| c.downcase.start_with?(query) }

      if matches.length == 1
        matches.first[@filter_text.length..]
      elsif matches.length > 1
        prefix = common_prefix(matches)
        remaining = prefix[@filter_text.length..] || ""
        remaining + " (#{matches.length} matches)"
      else
        " (no matches)"
      end
    end

    def common_prefix(strings)
      return "" if strings.empty?

      prefix = strings.first
      strings.each do |s|
        prefix = prefix[0...prefix.length].chars.take_while.with_index { |c, i| s[i]&.downcase == c.downcase }.join
      end
      prefix
    end

    def handle_normal_input(key)
      case key
      when "\e"
        next_chars = $stdin.read_nonblock(2) rescue nil
        case next_chars
        when "[A" # up
          @selected = [0, @selected - 1].max
          adjust_scroll
        when "[B" # down
          @selected = [@jobs.length - 1, @selected + 1].min
          adjust_scroll
        when nil # bare Escape — clear active filter
          if @filter_text.length > 0
            @filter_text = ""
            load_data
          end
        end
      when "q"
        throw(:quit)
      when "/"
        @filter_mode = true
        @filter_text = ""
      when ":"
        @command_mode = true
        @command_text = ""
      when "r"
        retry_selected
      when "d"
        discard_selected
      when " "
        load_data
      end
    end

    def switch_view(view)
      @view = view
      @selected = 0
      @scroll_offset = 0
      load_data
    end

    def handle_command_input(key)
      case key
      when "\r", "\n" # Enter — execute command
        execute_command
        @command_mode = false
        @command_text = ""
        print "\e[?25l"
      when "\e" # Escape — cancel (drain arrow key bytes)
        $stdin.read_nonblock(2) rescue nil
        @command_mode = false
        @command_text = ""
        print "\e[?25l"
      when "\t" # Tab — autocomplete
        autocomplete_command
      when "\u007F", "\b" # Backspace
        @command_text = @command_text[0..-2]
      else
        if key.match?(/[[:print:]]/)
          @command_text += key
        end
      end
    end

    def execute_command
      parts = @command_text.strip.split(/\s+/)
      return if parts.empty?

      case parts[0]
      when "sort"
        field = parts[1] || "created"
        direction = parts[2] || "desc"
        case field
        when "created"
          @sort_column = :created_at
        when "id"
          @sort_column = :id
        else
          @message = "Unknown sort field: #{field}"
          return
        end
        case direction
        when "asc"  then @sort_dir = :asc
        when "desc" then @sort_dir = :desc
        else
          @message = "Unknown sort direction: #{direction}"
          return
        end
        @selected = 0
        @scroll_offset = 0
        load_data
      when "view"
        target = parts[1] || "all"
        case target
        when "all"       then switch_view(:all)
        when "failed"    then switch_view(:failed)
        when "completed" then switch_view(:completed)
        when "pending"   then switch_view(:pending)
        else
          @message = "Unknown view: #{target}"
        end
      else
        @message = "Unknown command: #{parts[0]}"
      end
    end

    def autocomplete_command
      return if @command_text.empty?

      parts = @command_text.strip.split(/\s+/)
      # If text ends with space, we're starting a new word
      completing_new_word = @command_text.end_with?(" ")

      if completing_new_word
        case parts.length
        when 1
          # After first word + space, complete second word
          subtree = COMMANDS[parts[0]]
          return unless subtree.is_a?(Hash)
          completed = complete_word("", subtree.keys)
          @command_text = "#{parts[0]} #{completed}" if completed
        when 2
          # After second word + space, complete third word
          subtree = COMMANDS.dig(parts[0], parts[1])
          return unless subtree.is_a?(Array) && subtree.any?
          completed = complete_word("", subtree)
          @command_text = "#{parts[0]} #{parts[1]} #{completed}" if completed
        end
      else
        case parts.length
        when 1
          completed = complete_word(parts[0], COMMANDS.keys)
          @command_text = completed if completed
        when 2
          subtree = COMMANDS[parts[0]]
          return unless subtree.is_a?(Hash)
          completed = complete_word(parts[1], subtree.keys)
          @command_text = "#{parts[0]} #{completed}" if completed
        when 3
          subtree = COMMANDS.dig(parts[0], parts[1])
          return unless subtree.is_a?(Array) && subtree.any?
          completed = complete_word(parts[2], subtree)
          @command_text = "#{parts[0]} #{parts[1]} #{completed}" if completed
        end
      end
    end

    def complete_word(partial, candidates)
      matches = candidates.select { |c| c.downcase.start_with?(partial.downcase) }
      if matches.length == 1
        matches.first
      elsif matches.length > 1
        prefix = common_prefix(matches)
        # Only return if the prefix actually advances beyond what's typed
        prefix.length > partial.length ? prefix : nil
      end
    end

    def command_autocomplete_hint
      return "" if @command_text.empty?

      parts = @command_text.strip.split(/\s+/)
      completing_new_word = @command_text.end_with?(" ")

      if completing_new_word
        case parts.length
        when 1
          subtree = COMMANDS[parts[0]]
          return "" unless subtree.is_a?(Hash)
          hint_for_candidates("", subtree.keys)
        when 2
          subtree = COMMANDS.dig(parts[0], parts[1])
          return "" unless subtree.is_a?(Array) && subtree.any?
          hint_for_candidates("", subtree)
        else
          ""
        end
      else
        case parts.length
        when 1
          hint_for_candidates(parts[0], COMMANDS.keys)
        when 2
          subtree = COMMANDS[parts[0]]
          return "" unless subtree.is_a?(Hash)
          hint_for_candidates(parts[1], subtree.keys)
        when 3
          subtree = COMMANDS.dig(parts[0], parts[1])
          return "" unless subtree.is_a?(Array) && subtree.any?
          hint_for_candidates(parts[2], subtree)
        else
          ""
        end
      end
    end

    def hint_for_candidates(partial, candidates)
      matches = candidates.select { |c| c.downcase.start_with?(partial.downcase) }
      if matches.length == 1
        matches.first[partial.length..]
      elsif matches.length > 1
        prefix = common_prefix(matches)
        remaining = prefix[partial.length..] || ""
        remaining + " (#{matches.map { |m| m }.join("|")})"
      else
        " (no matches)"
      end
    end

    def retry_selected
      job = @jobs[@selected]
      return unless job

      failed = Models::FailedExecution.find_by(job_id: job.id)
      unless failed
        @message = "Job #{job.id} is not failed"
        return
      end

      failed.retry!
      @message = "Retried job #{job.id} (#{job.class_name})"
      load_data
    end

    def discard_selected
      job = @jobs[@selected]
      return unless job

      failed = Models::FailedExecution.find_by(job_id: job.id)
      unless failed
        @message = "Job #{job.id} is not failed"
        return
      end

      failed.discard!
      @message = "Discarded job #{job.id} (#{job.class_name})"
      load_data
    end
  end
end
