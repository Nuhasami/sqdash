# frozen_string_literal: true

require "io/console"
require "io/wait"

module Sqdash
  module InputHandler
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
          if @detail_job
            @detail_job.reload
          else
            load_data
          end
          draw_screen
          next
        end

        if @detail_job
          handle_detail_input(key)
        elsif @command_mode
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
      ready = $stdin.wait_readable(1)
      return nil unless ready

      $stdin.getc
    end

    def handle_normal_input(key)
      case key
      when "\e"
        next_chars = begin
          $stdin.read_nonblock(2)
        rescue StandardError
          nil
        end
        case next_chars
        when "[A" # up
          @selected = [0, @selected - 1].max
          adjust_scroll
        when "[B" # down
          max = [@jobs.length - 1, 0].max
          @selected = [max, @selected + 1].min
          adjust_scroll
        when nil # bare Escape — clear active filter or selection
          if @marked_ids.any?
            @marked_ids.clear
          elsif @filter_text.length.positive?
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
      when "x"
        toggle_mark
      when "X"
        toggle_mark_all
      when "r"
        retry_selected
      when "d"
        discard_selected
      when "\r", "\n"
        show_detail
      when " "
        load_data
      end
    end

    def handle_filter_input(key)
      case key
      when "\r", "\n"
        @filter_mode = false
        print "\e[?25l"
        load_data
      when "\e"
        begin
          $stdin.read_nonblock(2)
        rescue StandardError
          nil
        end
        @filter_mode = false
        @filter_text = ""
        print "\e[?25l"
        load_data
      when "\t"
        autocomplete_filter
      when "\u007F", "\b"
        @filter_text = @filter_text[0..-2]
        load_data
      else
        if key.match?(/[[:print:]]/)
          @filter_text += key
          load_data
        end
      end
    end

    def handle_command_input(key)
      case key
      when "\r", "\n"
        execute_command
        @command_mode = false
        @command_text = ""
        print "\e[?25l"
      when "\e"
        begin
          $stdin.read_nonblock(2)
        rescue StandardError
          nil
        end
        @command_mode = false
        @command_text = ""
        print "\e[?25l"
      when "\t"
        autocomplete_command
      when "\u007F", "\b"
        @command_text = @command_text[0..-2]
      else
        @command_text += key if key.match?(/[[:print:]]/)
      end
    end

    def handle_detail_input(key)
      case key
      when "\e"
        next_chars = begin
          $stdin.read_nonblock(2)
        rescue StandardError
          nil
        end
        case next_chars
        when "[A"
          @detail_scroll = [@detail_scroll - 1, 0].max
        when "[B"
          @detail_scroll += 1
        when nil
          @detail_job = nil
          full_draw
        end
      when "\u007F", "\b"
        @detail_job = nil
        full_draw
      when "r"
        failed = Models::FailedExecution.find_by(job_id: @detail_job.id)
        if failed
          failed.retry!
          @message = "Retried job #{@detail_job.id} (#{@detail_job.class_name})"
          @detail_job.reload
          load_data
        else
          @message = "Job #{@detail_job.id} is not failed"
        end
      when "d"
        failed = Models::FailedExecution.find_by(job_id: @detail_job.id)
        if failed
          failed.discard!
          @message = "Discarded job #{@detail_job.id} (#{@detail_job.class_name})"
          @detail_job = nil
          load_data
          full_draw
        else
          @message = "Job #{@detail_job.id} is not failed"
        end
      when "q"
        throw(:quit)
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

    def show_detail
      return if @jobs.empty?

      @detail_job = @jobs[@selected]
      @detail_scroll = 0
      full_draw
    end

    def switch_view(view)
      @view = view
      @selected = 0
      @scroll_offset = 0
      @marked_ids.clear
      load_data
    end

    def toggle_mark
      job = @jobs[@selected]
      return unless job

      if @marked_ids.include?(job.id)
        @marked_ids.delete(job.id)
      else
        @marked_ids.add(job.id)
      end
    end

    def toggle_mark_all
      visible_ids = @jobs.map(&:id)
      if visible_ids.all? { |id| @marked_ids.include?(id) }
        visible_ids.each { |id| @marked_ids.delete(id) }
      else
        visible_ids.each { |id| @marked_ids.add(id) }
      end
    end

    def retry_selected
      if @marked_ids.any?
        bulk_retry
      else
        retry_single
      end
    end

    def discard_selected
      if @marked_ids.any?
        bulk_discard
      else
        discard_single
      end
    end

    def retry_single
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

    def discard_single
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

    def bulk_retry
      bulk_action(:retry!, "Retried")
    end

    def bulk_discard
      bulk_action(:discard!, "Discarded")
    end

    def bulk_action(method, verb)
      failed = Models::FailedExecution.where(job_id: @marked_ids.to_a)
      count = 0
      errors = 0
      failed.each do |f|
        f.public_send(method)
        count += 1
      rescue StandardError
        errors += 1
      end
      skipped = @marked_ids.size - count - errors
      @message = "#{verb} #{count} job#{'s' unless count == 1}"
      @message += " (#{skipped} skipped)" if skipped.positive?
      @message += " (#{errors} failed)" if errors.positive?
      @marked_ids.clear
      load_data
    end
  end
end
