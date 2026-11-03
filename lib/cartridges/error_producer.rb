# frozen_string_literal: true

require "monitor"

module Cartridges
  # ErrorProducer is the mixin for objects that produce errors: it adds
  # report_error and collect_errors, both guarded by a mutex because the
  # managers report from worker threads while the importer collects from the
  # main loop.
  #
  # Ported from cartridges/errors/error_producer.py.
  module ErrorProducer
    def errors = @errors ||= []
    def errors_lock = @errors_lock ||= Monitor.new

    def report_error(error)
      errors_lock.synchronize { errors << error }
    end

    # Collects and removes the errors produced so far.
    def collect_errors
      errors_lock.synchronize do
        errors.dup.tap { errors.clear }
      end
    end
  end
end
