# frozen_string_literal: true

require_relative "../../error_producer"
require_relative "../../friendly_error"
require_relative "../../logging/setup"

module Cartridges
  class Store
    # Manager is the base class for the post-creation actions a game goes
    # through: saving it, fetching its metadata, downloading its cover, adding
    # its tile to the library. A manager may connect to signals on the game,
    # retry on the error types it lists, skip the ones it continues on, and
    # report everything else for the importer to show.
    #
    # Ported from cartridges/store/managers/manager.py. Python's class
    # attributes inherit, so the class-level readers below walk up the
    # superclass chain rather than defaulting per subclass.
    class Manager
      include ErrorProducer

      class << self
        attr_writer :run_after, :retryable_on, :continue_on, :signals,
                    :blocking, :retry_delay, :max_tries

        # The manager types that must be done before this one may run.
        def run_after = inherited_attribute(:run_after, [])

        # Whether the pipeline runs this manager on the calling thread.
        def blocking = inherited_attribute(:blocking, true)

        # Error types a failed run is retried on.
        def retryable_on = inherited_attribute(:retryable_on, [])

        # Error types a failed run is skipped silently on.
        def continue_on = inherited_attribute(:continue_on, [])

        # The game signals this manager runs in response to.
        def signals = inherited_attribute(:signals, [])

        def retry_delay = inherited_attribute(:retry_delay, 3)
        def max_tries = inherited_attribute(:max_tries, 3)

        def inherited_attribute(attribute, default)
          if instance_variable_defined?(:"@#{attribute}")
            instance_variable_get(:"@#{attribute}")
          elsif superclass.respond_to?(attribute)
            superclass.public_send(attribute)
          else
            default
          end
        end
      end

      def name = self.class.name.to_s.split("::").last
      def run_after = self.class.run_after
      def blocking = self.class.blocking
      def retryable_on = self.class.retryable_on
      def continue_on = self.class.continue_on
      def signals = self.class.signals
      def retry_delay = self.class.retry_delay
      def max_tries = self.class.max_tries

      # The manager-specific logic, implemented by the final subclasses. It
      # may block its thread, and may raise either a retryable error or one
      # that gets reported.
      def main(_game, _additional_data)
        raise NotImplementedError, "#{name} must implement main"
      end

      # Runs main, retrying, skipping or reporting whatever it raises.
      def run(game, additional_data)
        attempt(game, additional_data, 1)
      end

      # Passes the game through the manager, then tells the pipeline it is
      # done. Overridden by AsyncManager to do it on another thread.
      def process_game(game, additional_data, callback)
        run(game, additional_data)
        callback.call(self)
      end

      private

        def attempt(game, additional_data, tries)
          main(game, additional_data)
        rescue StandardError => e
          handle_error(e, game, additional_data, tries)
        end

        def handle_error(error, game, additional_data, tries)
          # A FriendlyError wraps the real cause; the retry rules apply to
          # the cause, while the friendly wrapper is what gets reported.
          underlying(error).then do |cause|
            if continue_on.any? { |type| cause.is_a?(type) }
              nil
            elsif retryable_on.any? { |type| cause.is_a?(type) }
              retry_or_report(error, cause, game, additional_data, tries)
            else
              Logging.logger.error("Unretryable #{cause.class.name} in #{name} for #{describe(game)}")
              report_error(error)
            end
          end
        end

        def retry_or_report(error, cause, game, additional_data, tries)
          if tries > max_tries
            Logging.logger.error("Out of retries due to #{cause.class.name} in #{name} for #{describe(game)}")
            report_error(error)
          else
            Logging.logger.error("Retrying #{cause.class.name} in #{name} for #{describe(game)}")
            sleep(retry_delay)
            attempt(game, additional_data, tries + 1)
          end
        end

        def underlying(error)
          if error.is_a?(FriendlyError) && error.original_cause
            error.original_cause
          else
            error
          end
        end

        def describe(game) = "#{game.name} (#{game.game_id})"
    end
  end
end
