# frozen_string_literal: true

module Cartridges
  # FriendlyError is an error meant to be shown to the user in a nice format:
  # a title and a subtitle, each a format string with its own arguments.
  #
  # Ported from cartridges/errors/friendly_error.py. Python's `raise ... from
  # ...` is spelled here by passing the original exception as `cause`, which
  # the managers read when they decide whether an error is retryable.
  class FriendlyError < StandardError
    attr_reader :title_format, :title_args, :subtitle_format, :subtitle_args, :original_cause

    def initialize(title, subtitle, title_args: [], subtitle_args: [], cause: nil)
      @title_format = title
      @subtitle_format = subtitle
      @title_args = title_args
      @subtitle_args = subtitle_args
      @original_cause = cause
      super("#{format_with(title, title_args)} - #{format_with(subtitle, subtitle_args)}")
    end

    def title = format_with(@title_format, @title_args)
    def subtitle = format_with(@subtitle_format, @subtitle_args)
    def to_s = "#{title} - #{subtitle}"

    private

      # Upstream calls str.format(args), which substitutes the whole argument
      # tuple into the single `{}` placeholder; an empty tuple leaves the
      # format string as the user sees it.
      def format_with(string, args)
        Array(args).then do |list|
          if list.empty?
            string.to_s
          else
            string.to_s.sub("{}", list.join(", "))
          end
        end
      end
  end
end
