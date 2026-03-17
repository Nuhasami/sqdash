# frozen_string_literal: true

module Sqdash
  class CLI
    include Renderer
    include InputHandler
    include Autocomplete

    DEFAULT_DB_URL = "postgres://sqd:sqd@localhost:5432/sqd_web_development_queue"

    HELP_TEXT = <<~HELP
      Usage: sqdash [database-url] [options]

      A terminal dashboard for Rails 8's Solid Queue.

      Arguments:
        database-url    Database connection URL (optional)

      Options:
        -c, --config FILE   Path to config file (default: .sqdash.yml or ~/.sqdash.yml)
        -h, --help          Show this help message
        -v, --version       Show version

      Config file (~/.sqdash.yml or .sqdash.yml):
        database_url: postgres://user:pass@host:5432/myapp

      Connection priority: CLI arg > DATABASE_URL env > .sqdash.yml > ~/.sqdash.yml > default

      Keybindings:
        ↑/↓             Navigate job list
        Enter            View job details
        /                Filter jobs (by class, queue, or ID)
        :                Command mode (sort, view)
        r                Retry failed job
        d                Discard failed job
        Space            Refresh data
        q                Quit

      Commands (in : mode):
        sort created|id asc|desc    Sort jobs
        view all|failed|completed|pending    Filter by status

      Examples:
        sqdash
        sqdash postgres://user:pass@host:5432/myapp_production
        DATABASE_URL=postgres://... sqdash
    HELP

    COMMANDS = {
      "sort" => {
        "created" => %w[asc desc],
        "id" => %w[asc desc]
      },
      "view" => {
        "all" => [],
        "failed" => [],
        "completed" => [],
        "pending" => []
      }
    }.freeze

    def self.start
      args = ARGV.dup
      config_path = nil

      if (idx = args.index("-c") || args.index("--config"))
        args.delete_at(idx)
        config_path = args.delete_at(idx)
      end

      case args[0]
      when "-h", "--help"
        puts HELP_TEXT
        exit
      when "-v", "--version"
        puts "sqdash #{Sqdash::VERSION}"
        exit
      end

      new(db_url: args[0], config_path: config_path).run
    end

    def initialize(db_url: nil, config_path: nil)
      @db_url_arg = db_url
      @config_path = config_path
    end

    def run
      Database.connect!(resolve_db_url)
      @selected = 0
      @scroll_offset = 0
      @filter_text = ""
      @filter_mode = false
      @view = :all
      @jobs = []
      @failed_ids = []
      @message = nil
      @sort_column = :created_at
      @sort_dir = :desc
      @command_mode = false
      @command_text = ""
      @detail_job = nil
      @detail_scroll = 0
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
      @db_url_arg ||
        ENV["DATABASE_URL"] ||
        Config.load(@config_path).database_url ||
        DEFAULT_DB_URL
    end

    def trap_resize
      Signal.trap("WINCH") do
        @needs_redraw = true
      end
    end

    def load_data
      @failed_ids = Models::FailedExecution.pluck(:job_id)

      scope = Models::Job.order(@sort_column => @sort_dir)

      case @view
      when :failed
        scope = @failed_ids.any? ? scope.where(id: @failed_ids) : scope.none
      when :completed
        scope = scope.where.not(finished_at: nil).where.not(id: @failed_ids)
      when :pending
        scope = scope.where(finished_at: nil).where.not(id: @failed_ids)
      end

      @jobs = scope.to_a

      if @filter_text.length.positive?
        query = @filter_text.downcase
        @jobs = @jobs.select do |job|
          job.class_name.downcase.include?(query) ||
            job.queue_name.downcase.include?(query) ||
            job.id.to_s.include?(query)
        end
      end

      @selected = @selected.clamp(0, [@jobs.length - 1, 0].max)
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
  end
end
