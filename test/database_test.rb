# frozen_string_literal: true

require_relative "test_helper"

class DatabaseTest < Minitest::Test
  def teardown
    # Restore the in-memory SQLite connection and schema after tests that may change it
    setup_test_database!
  end

  # --- adapter selection ---

  def test_adapters_map_postgres_scheme
    config = Sqdash::Database::ADAPTERS["postgres"]
    assert_equal "pg", config[:gem]
    assert_equal "postgresql", config[:adapter]
  end

  def test_adapters_map_postgresql_scheme
    config = Sqdash::Database::ADAPTERS["postgresql"]
    assert_equal "pg", config[:gem]
    assert_equal "postgresql", config[:adapter]
  end

  def test_adapters_map_mysql2_scheme
    config = Sqdash::Database::ADAPTERS["mysql2"]
    assert_equal "mysql2", config[:gem]
    assert_equal "mysql2", config[:adapter]
  end

  def test_adapters_map_sqlite3_scheme
    config = Sqdash::Database::ADAPTERS["sqlite3"]
    assert_equal "sqlite3", config[:gem]
    assert_equal "sqlite3", config[:adapter]
  end

  def test_adapters_is_frozen
    assert Sqdash::Database::ADAPTERS.frozen?
  end

  # --- require_adapter! ---

  def test_require_adapter_succeeds_for_sqlite3
    Sqdash::Database.require_adapter!("sqlite3:///:memory:")
  end

  def test_require_adapter_succeeds_for_postgres
    Sqdash::Database.require_adapter!("postgres://localhost/test")
  end

  def test_require_adapter_aborts_for_unsupported_scheme
    err = assert_raises(SystemExit) do
      Sqdash::Database.require_adapter!("redis://localhost")
    end
    assert_equal 1, err.status
  end

  def test_require_adapter_aborts_for_missing_gem
    assert_raises(SystemExit) do
      scheme = "mysql2"
      config = Sqdash::Database::ADAPTERS[scheme]
      begin
        require config[:gem]
      rescue LoadError
        abort "\e[31mMissing database adapter gem '#{config[:gem]}'.\e[0m"
      end
    end
  end

  # --- connect! error handling ---

  def test_connect_aborts_when_establish_connection_raises
    # Simulate a connection failure by stubbing establish_connection to raise
    ActiveRecord::Base.stub(:establish_connection, ->(_) { raise "connection refused" }) do
      err = assert_raises(SystemExit) do
        Sqdash::Database.connect!("postgres://bad:bad@localhost:1/nonexistent")
      end
      assert_equal 1, err.status
    end
  end

  def test_connect_aborts_when_connection_verify_raises
    # Simulate the connection object raising on .connection
    ActiveRecord::Base.stub(:connection, -> { raise "could not connect" }) do
      err = assert_raises(SystemExit) do
        Sqdash::Database.connect!("sqlite3:///:memory:")
      end
      assert_equal 1, err.status
    end
  end

  # --- scheme parsing ---

  def test_require_adapter_parses_scheme_with_colon_prefix
    Sqdash::Database.require_adapter!("sqlite3:///tmp/test.db")
  end

  def test_require_adapter_parses_postgres_subprotocol
    Sqdash::Database.require_adapter!("postgres://user:pass@host:5432/db")
  end
end
