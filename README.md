# sqdash: Solid Queue Terminal Dashboard

A terminal dashboard for Rails 8's Solid Queue.

Solid Queue is the default Active Job backend in Rails 8, but it ships with no built-in UI. sqdash gives you a fast, keyboard-driven TUI to monitor and manage jobs without leaving your terminal — no browser, no extra server, no mounted routes.

![sqdash demo](demo.gif)

## Features

- Live overview of all Solid Queue jobs with status, queue, and timestamps
- Paginated loading — handles 100k+ jobs without slowing down
- View filters: all, failed, completed, pending
- Sortable by created date or ID, ascending or descending
- Fuzzy text filter across job class, queue name, and ID
- Retry or discard failed jobs with a single keypress
- k9s-style `:` command bar with Tab autocomplete
- `/` search with inline autocomplete hints
- Job detail view with arguments, timestamps, and error backtraces

## Installation

```bash
gem install sqdash
```

Or add it to your Gemfile:

```bash
bundle add sqdash
```

## Prerequisites

sqdash connects directly to your Solid Queue database. You need:

- A database with the Solid Queue schema (`solid_queue_*` tables) — PostgreSQL, MySQL, or SQLite
- Ruby >= 3.2
- The database adapter gem for your database:

```bash
gem install pg       # PostgreSQL
gem install mysql2   # MySQL
gem install sqlite3  # SQLite
```

## Usage

```bash
sqdash --help       # Show usage and keybindings
sqdash --version    # Show version
```

```bash
# PostgreSQL
sqdash postgres://user:pass@localhost:5432/myapp_queue

# MySQL
sqdash mysql2://user:pass@localhost:3306/myapp_queue

# SQLite
sqdash sqlite3:///path/to/queue.db

# Or set the DATABASE_URL environment variable
export DATABASE_URL=postgres://user:pass@localhost:5432/myapp_queue
sqdash

# Use a specific config file
sqdash --config /path/to/config.yml

# Falls back to default: postgres://sqd:sqd@localhost:5432/sqd_web_development_queue
sqdash
```

Connection priority: **CLI argument** > **`DATABASE_URL` env var** > **`.sqdash.yml`** > **`~/.sqdash.yml`** > **built-in default**.

### Config file

Instead of passing a database URL every time, create a `.sqdash.yml` file in your project directory or home directory:

```yaml
# .sqdash.yml or ~/.sqdash.yml
database_url: postgres://user:pass@localhost:5432/myapp_queue
```

A project-local `.sqdash.yml` takes precedence over `~/.sqdash.yml`. You can also specify a config file explicitly with `--config` / `-c`.

## How to use

Once connected, sqdash shows a live dashboard of all your Solid Queue jobs. Here are common workflows:

### Quick start

```bash
# Connect to your Rails app's queue database
sqdash postgres://user:pass@localhost:5432/myapp_development

# Or if you have a .sqdash.yml config file, just run:
sqdash
```

### Investigating failed jobs

1. Type `:view failed` and press `Enter` to show only failed jobs
2. Use `↑`/`↓` to select a job
3. Press `Enter` to see the full error backtrace and job arguments
4. Press `r` to retry the job, or `d` to discard it
5. Press `Esc` to go back to the list

For bulk actions, press `x` to mark multiple jobs, then `r` or `d` to retry or discard all marked jobs at once. Press `X` to select all.

### Finding a specific job

1. Press `/` to open the search filter
2. Start typing a job class name (e.g., `UserMailer`), queue name, or job ID
3. Press `Tab` to autocomplete — sqdash suggests matching class and queue names
4. Press `Enter` to apply the filter
5. Press `Esc` to clear the filter and see all jobs again

### Sorting jobs

1. Press `:` to open the command bar
2. Type `sort created asc` to see oldest jobs first (useful for finding stuck jobs)
3. Press `Enter` to apply
4. Other options: `sort created desc` (default), `sort id asc`, `sort id desc`

### Monitoring a queue in real time

sqdash auto-refreshes data every second when idle. You can also press `Space` to manually refresh. The stats bar at the top shows live counts of total, completed, failed, and pending jobs.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate job list |
| `↵` | Open job detail view |
| `x` | Toggle select job (for bulk actions) |
| `X` | Select/deselect all jobs |
| `/` | Filter jobs (fuzzy search across all columns) |
| `:` | Command bar (sort, switch views) |
| `Tab` | Autocomplete (in filter or command mode) |
| `r` | Retry failed job(s) — bulk if selected |
| `d` | Discard failed job(s) — bulk if selected |
| `Esc` | Clear selection, filter, or go back |
| `Space` | Refresh data |
| `q` | Quit |

### Commands

Type `:` to open the command bar, then:

| Command | Description |
|---------|-------------|
| `sort created desc` | Sort by created date, newest first (default) |
| `sort created asc` | Sort by created date, oldest first |
| `sort id desc` | Sort by job ID, highest first |
| `sort id asc` | Sort by job ID, lowest first |
| `view all` | Show all jobs |
| `view failed` | Show only failed jobs |
| `view completed` | Show only completed jobs |
| `view pending` | Show only pending jobs |

Arguments are optional — `sort` defaults to `sort created desc`, `view` defaults to `view all`.

## Development

```bash
git clone https://github.com/nuhasami/sqdash.git
cd sqdash
bin/setup
bundle exec ruby exe/sqdash
rake test
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nuhasami/sqdash.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
