# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require "sqlite3"

# Suppress schema output
ActiveRecord::Migration.verbose = false

def setup_test_database!
  ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

  ActiveRecord::Schema.define do
    create_table :solid_queue_jobs, force: true do |t|
      t.string :class_name, null: false
      t.string :queue_name, null: false
      t.integer :priority, default: 0
      t.string :active_job_id
      t.text :arguments
      t.datetime :scheduled_at
      t.datetime :finished_at
      t.timestamps
    end

    create_table :solid_queue_failed_executions, force: true do |t|
      t.integer :job_id, null: false
      t.text :error
      t.timestamps
    end

    create_table :solid_queue_ready_executions, force: true do |t|
      t.integer :job_id, null: false
      t.string :queue_name, null: false
      t.integer :priority, default: 0
      t.timestamps
    end
  end
end

setup_test_database!

require_relative "../lib/sqdash"
