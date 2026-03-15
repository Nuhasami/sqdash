# frozen_string_literal: true

require "active_record"

module Sqd
  class Database
    def self.connect!(url)
      ActiveRecord::Base.establish_connection(url)
      ActiveRecord::Base.connection # test the connection
    rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
      puts "\e[31mFailed to connect to database: #{e.message}\e[0m"
      exit 1
    end
  end
end
