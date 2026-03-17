# frozen_string_literal: true

require "yaml"

module Sqdash
  class Config
    CONFIG_FILENAME = ".sqdash.yml"

    def self.load(path = nil)
      new(path)
    end

    def initialize(path = nil)
      @data = {}
      file = path || find_config_file
      return unless file

      @data = YAML.safe_load_file(file) || {}
    rescue Errno::ENOENT
      # Explicit path given but file not found
      abort "\e[31mConfig file not found: #{path}\e[0m" if path
    rescue Psych::SyntaxError => e
      abort "\e[31mInvalid YAML in #{file}: #{e.message}\e[0m"
    end

    def database_url
      @data["database_url"]
    end

    private

    def find_config_file
      [
        File.join(Dir.pwd, CONFIG_FILENAME),
        File.join(Dir.home, CONFIG_FILENAME)
      ].find { |p| File.exist?(p) }
    end
  end
end
