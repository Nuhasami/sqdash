# sqdash: Solid Queue Terminal Dashboard

A terminal dashboard for Rails 8's Solid Queue.

Solid Queue is the default Active Job backend in Rails 8, but it ships with no built-in UI. sqdash gives you a fast, keyboard-driven TUI to monitor and manage jobs without leaving your terminal — no browser, no extra server, no mounted routes.

## Features

- Live overview of all Solid Queue jobs with status, queue, and timestamps
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
- Ruby >= 3.0
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

# Falls back to default: postgres://sqd:sqd@localhost:5432/sqd_web_development_queue
sqdash
```

Connection priority: **CLI argument** > **`DATABASE_URL` env var** > **built-in default**.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate job list |
| `Enter` | Open job detail view |
| `/` | Filter jobs (fuzzy search across all columns) |
| `:` | Command bar (sort, switch views) |
| `Tab` | Autocomplete (in filter or command mode) |
| `r` | Retry selected failed job |
| `d` | Discard selected failed job |
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
