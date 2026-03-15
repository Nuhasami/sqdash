# frozen_string_literal: true

require "active_record"

module Sqdash
  class Database
    ADAPTERS = {
      "postgres" => { gem: "pg", adapter: "postgresql" },
      "postgresql" => { gem: "pg", adapter: "postgresql" },
      "mysql2" => { gem: "mysql2", adapter: "mysql2" },
      "sqlite3" => { gem: "sqlite3", adapter: "sqlite3" }
    }.freeze

    def self.connect!(url)
      require_adapter!(url)
      ActiveRecord::Base.establish_connection(url)
      ActiveRecord::Base.connection
    rescue => e
      abort "\e[31mFailed to connect: #{e.message}\e[0m\n\n" \
            "Usage: sqdash <database-url>\n" \
            "Run sqdash --help for details."
    end

    def self.require_adapter!(url)
      scheme = url.split("://").first.split(":").first
      config = ADAPTERS[scheme]

      unless config
        abort "\e[31mUnsupported database adapter: #{scheme}\n" \
              "Supported: postgres, mysql2, sqlite3\e[0m"
      end

      require config[:gem]
    rescue LoadError
      abort "\e[31mMissing database adapter gem '#{config[:gem]}'. Install it with:\n" \
            "  gem install #{config[:gem]}\e[0m"
    end
  end
end
