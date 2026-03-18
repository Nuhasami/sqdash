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
        ↵                View job details
        x                Toggle select job (for bulk actions)
        X                Select/deselect all visible jobs
        /                Filter jobs (by class, queue, or ID)
        :                Command mode (sort, view)
        r                Retry failed job(s) — bulk if selected
        d                Discard failed job(s) — bulk if selected
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

    PAGE_SIZE = 200

    def run
      Database.connect!(resolve_db_url)
      @selected = 0
      @scroll_offset = 0
      @filter_text = ""
      @filter_mode = false
      @view = :all
      @jobs = []
      @failed_ids = []
      @total_count = 0
      @page = 0
      @all_loaded = false
      @message = nil
      @sort_column = :created_at
      @sort_dir = :desc
      @command_mode = false
      @command_text = ""
      @detail_job = nil
      @detail_scroll = 0
      @marked_ids = Set.new
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
      @page = 0
      @all_loaded = false

      scope = build_scope
      @total_count = scope.count
      @jobs = scope.limit(PAGE_SIZE).offset(0).to_a
      @all_loaded = @jobs.length < PAGE_SIZE

      @selected = @selected.clamp(0, [@jobs.length - 1, 0].max)
      adjust_scroll
    end

    def load_more
      return if @all_loaded

      @page += 1
      new_jobs = build_scope.limit(PAGE_SIZE).offset(@page * PAGE_SIZE).to_a
      @jobs.concat(new_jobs)
      @all_loaded = new_jobs.length < PAGE_SIZE
    end

    def build_scope
      scope = Models::Job.order(@sort_column => @sort_dir)

      case @view
      when :failed
        scope = @failed_ids.any? ? scope.where(id: @failed_ids) : scope.none
      when :completed
        scope = scope.where.not(finished_at: nil).where.not(id: @failed_ids)
      when :pending
        scope = scope.where(finished_at: nil).where.not(id: @failed_ids)
      end

      if @filter_text.length.positive?
        query = "%#{@filter_text}%"
        scope = scope.where(
          "LOWER(class_name) LIKE LOWER(?) OR LOWER(queue_name) LIKE LOWER(?) OR CAST(id AS TEXT) LIKE ?",
          query, query, query
        )
      end

      scope
    end

    def adjust_scroll
      if @selected < @scroll_offset
        @scroll_offset = @selected
      elsif @selected >= @scroll_offset + visible_rows
        @scroll_offset = @selected - visible_rows + 1
      end

      load_more if !@all_loaded && @selected >= @jobs.length - (PAGE_SIZE / 4)
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
