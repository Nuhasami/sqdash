# sqd

A terminal dashboard for Rails 8's Solid Queue.

Solid Queue is the default Active Job backend in Rails 8, but it ships with no built-in UI. sqd gives you a fast, keyboard-driven TUI to monitor and manage jobs without leaving your terminal — no browser, no extra server, no mounted routes.

## Features

- Live overview of all Solid Queue jobs with status, queue, and timestamps
- View filters: all, failed, completed, pending
- Sortable by created date or ID, ascending or descending
- Fuzzy text filter across job class, queue name, and ID
- Retry or discard failed jobs with a single keypress
- k9s-style `:` command bar with Tab autocomplete
- `/` search with inline autocomplete hints

## Installation

```bash
gem install sqd
```

Or add it to your Gemfile:

```bash
bundle add sqd
```

## Prerequisites

sqd connects directly to your Solid Queue database. You need:

- PostgreSQL with a Solid Queue schema (the `solid_queue_*` tables)
- Ruby >= 3.0

## Usage

```bash
# Connect using a CLI argument
sqd postgres://user:pass@localhost:5432/myapp_queue

# Or set the DATABASE_URL environment variable
export DATABASE_URL=postgres://user:pass@localhost:5432/myapp_queue
sqd

# Falls back to default: postgres://sqd:sqd@localhost:5432/sqd_web_development_queue
sqd
```

Connection priority: **CLI argument** > **`DATABASE_URL` env var** > **built-in default**.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate job list |
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
git clone https://github.com/nuhasami/sqd.git
cd sqd
bin/setup
bundle exec ruby exe/sqd
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nuhasami/sqd.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
