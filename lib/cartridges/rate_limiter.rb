# frozen_string_literal: true

require "monitor"

module Cartridges
  # PickHistory counts how many tokens a rate limiter handed out inside its
  # refill period, discarding entries that have aged out.
  #
  # Ported from the PickHistory class in cartridges/utils/rate_limiter.py.
  class PickHistory
    attr_reader :period

    def initialize(period)
      @period = period
      @timestamps = []
      @lock = Monitor.new
    end

    # Drops history entries older than the period.
    def remove_old_entries
      (Time.now.to_f - @period).then do |cutoff|
        @lock.synchronize { @timestamps.select! { |entry| entry > cutoff } }
      end
    end

    # Adds timestamps to the history, or the current time when given none.
    def add(*new_timestamps)
      new_timestamps.then do |stamps|
        if stamps.empty?
          stamps = [Time.now.to_f]
        end
        @lock.synchronize { @timestamps.concat(stamps.map(&:to_f)) }
      end
    end

    # How many entries were logged in the period.
    def size
      remove_old_entries
      @lock.synchronize { @timestamps.length }
    end
    alias length size

    # The time the history started, or now when it is empty.
    def start
      remove_old_entries
      @lock.synchronize { @timestamps.first || Time.now.to_f }
    end

    def copy_timestamps
      remove_old_entries
      @lock.synchronize { @timestamps.dup }
    end
  end

  # RateLimiter is the token bucket the Steam web API calls go through. A
  # background thread drips tokens back into the bucket, spaced so that a
  # burst cannot push the period over its limit, and acquire blocks until the
  # caller's turn comes round.
  #
  # Ported from cartridges/utils/rate_limiter.py. Upstream builds the queue
  # out of a deque of Locks; this uses a ticket number under one monitor,
  # which gives the same first-come-first-served order.
  #
  # Subclasses must set refill_period_seconds, refill_period_tokens and
  # burst_tokens.
  class RateLimiter
    attr_reader :pick_history

    class << self
      attr_accessor :refill_period_seconds, :refill_period_tokens, :burst_tokens
    end

    def refill_period_seconds = self.class.refill_period_seconds
    def refill_period_tokens = self.class.refill_period_tokens
    def burst_tokens = self.class.burst_tokens

    def initialize
      init_pick_history
      @monitor = Monitor.new
      @condition = @monitor.new_cond
      @n_tokens = burst_tokens
      @next_ticket = 0
      @serving = 0
      @refill_thread = Thread.new { refill_loop }
      @refill_thread.abort_on_exception = false
    end

    def n_tokens = @monitor.synchronize { @n_tokens }

    # The spacing between refills, which shrinks the remaining tokens over the
    # time left in the period but never drops below the natural spacing.
    def refill_spacing
      (refill_period_tokens - @pick_history.size).then do |tokens_left|
        (@pick_history.start + refill_period_seconds - Time.now.to_f).then do |seconds_left|
          [refill_period_seconds.to_f / refill_period_tokens, spacing(tokens_left, seconds_left)].max
        end
      end
    end

    # Waits for a token and takes it, logging the pick in the history.
    def acquire
      @monitor.synchronize do
        @next_ticket.then do |ticket|
          @next_ticket += 1
          @condition.wait_while { @serving != ticket || !@n_tokens.positive? }
          @serving += 1
          @n_tokens -= 1
          # The next ticket holder may be able to go straight away, so wake
          # the queue rather than leaving it to the refill thread.
          @condition.broadcast
        end
      end
      @pick_history.add
    end

    # The with-statement form upstream uses: `with self.rate_limiter:`.
    def with_token
      acquire
      yield
    end

    private

      # Creates an empty pick history. Subclasses extend this to seed the
      # history from somewhere persistent.
      def init_pick_history
        @pick_history = PickHistory.new(refill_period_seconds)
      end

      def spacing(tokens_left, seconds_left)
        if tokens_left.positive?
          seconds_left / tokens_left
        else
          seconds_left
        end
      end

      def refill_loop
        loop { refill }
      end

      def refill
        sleep(refill_spacing)
        @monitor.synchronize do
          if @n_tokens < burst_tokens
            @n_tokens += 1
            @condition.broadcast
          end
        end
      end
  end
end
