# frozen_string_literal: true

module Sqdash
  module Autocomplete
    def autocomplete_filter
      return if @filter_text.empty?

      query = @filter_text.downcase

      candidates = (
        Models::Job.distinct.pluck(:class_name) +
        Models::Job.distinct.pluck(:queue_name)
      ).uniq

      matches = candidates.select { |c| c.downcase.start_with?(query) }

      if matches.length == 1
        @filter_text = matches.first
      elsif matches.length > 1
        @filter_text = common_prefix(matches)
      end

      load_data
    end

    def autocomplete_hint
      return "" if @filter_text.empty?

      query = @filter_text.downcase
      candidates = (
        Models::Job.distinct.pluck(:class_name) +
        Models::Job.distinct.pluck(:queue_name)
      ).uniq

      matches = candidates.select { |c| c.downcase.start_with?(query) }

      if matches.length == 1
        matches.first[@filter_text.length..]
      elsif matches.length > 1
        prefix = common_prefix(matches)
        remaining = prefix[@filter_text.length..] || ""
        remaining + " (#{matches.length} matches)"
      else
        " (no matches)"
      end
    end

    def autocomplete_command
      return if @command_text.empty?

      parts = @command_text.strip.split(/\s+/)
      completing_new_word = @command_text.end_with?(" ")

      if completing_new_word
        case parts.length
        when 1
          subtree = CLI::COMMANDS[parts[0]]
          return unless subtree.is_a?(Hash)

          completed = complete_word("", subtree.keys)
          @command_text = "#{parts[0]} #{completed}" if completed
        when 2
          subtree = CLI::COMMANDS.dig(parts[0], parts[1])
          return unless subtree.is_a?(Array) && subtree.any?

          completed = complete_word("", subtree)
          @command_text = "#{parts[0]} #{parts[1]} #{completed}" if completed
        end
      else
        case parts.length
        when 1
          completed = complete_word(parts[0], CLI::COMMANDS.keys)
          @command_text = completed if completed
        when 2
          subtree = CLI::COMMANDS[parts[0]]
          return unless subtree.is_a?(Hash)

          completed = complete_word(parts[1], subtree.keys)
          @command_text = "#{parts[0]} #{completed}" if completed
        when 3
          subtree = CLI::COMMANDS.dig(parts[0], parts[1])
          return unless subtree.is_a?(Array) && subtree.any?

          completed = complete_word(parts[2], subtree)
          @command_text = "#{parts[0]} #{parts[1]} #{completed}" if completed
        end
      end
    end

    def command_autocomplete_hint
      return "" if @command_text.empty?

      parts = @command_text.strip.split(/\s+/)
      completing_new_word = @command_text.end_with?(" ")

      if completing_new_word
        case parts.length
        when 1
          subtree = CLI::COMMANDS[parts[0]]
          return "" unless subtree.is_a?(Hash)

          hint_for_candidates("", subtree.keys)
        when 2
          subtree = CLI::COMMANDS.dig(parts[0], parts[1])
          return "" unless subtree.is_a?(Array) && subtree.any?

          hint_for_candidates("", subtree)
        else
          ""
        end
      else
        case parts.length
        when 1
          hint_for_candidates(parts[0], CLI::COMMANDS.keys)
        when 2
          subtree = CLI::COMMANDS[parts[0]]
          return "" unless subtree.is_a?(Hash)

          hint_for_candidates(parts[1], subtree.keys)
        when 3
          subtree = CLI::COMMANDS.dig(parts[0], parts[1])
          return "" unless subtree.is_a?(Array) && subtree.any?

          hint_for_candidates(parts[2], subtree)
        else
          ""
        end
      end
    end

    def complete_word(partial, candidates)
      matches = candidates.select { |c| c.downcase.start_with?(partial.downcase) }
      if matches.length == 1
        matches.first
      elsif matches.length > 1
        prefix = common_prefix(matches)
        prefix.length > partial.length ? prefix : nil
      end
    end

    def common_prefix(strings)
      return "" if strings.empty?

      prefix = strings.first
      strings.each do |s|
        prefix = prefix[0...prefix.length].chars.take_while.with_index { |c, i| s[i]&.downcase == c.downcase }.join
      end
      prefix
    end

    def hint_for_candidates(partial, candidates)
      matches = candidates.select { |c| c.downcase.start_with?(partial.downcase) }
      if matches.length == 1
        matches.first[partial.length..]
      elsif matches.length > 1
        prefix = common_prefix(matches)
        remaining = prefix[partial.length..] || ""
        remaining + " (#{matches.join('|')})"
      else
        " (no matches)"
      end
    end
  end
end
