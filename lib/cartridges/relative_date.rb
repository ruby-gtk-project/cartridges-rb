# frozen_string_literal: true

module Cartridges
  # RelativeDate formats the Unix timestamps the details page shows as "Added"
  # and "Last played" the way a person reads a date: Today, Yesterday, the
  # weekday name, Last Week, This Month, Last Month, the month name, Last Year,
  # then the year.
  #
  # Ported from cartridges/utils/relative_date.py.
  module RelativeDate
    class << self
      def format(timestamp)
        Time.now.then do |today|
          days(today, timestamp).then do |days_no|
            describe(days_no, today, timestamp)
          end
        end
      end

      private

        # Python's datetime subtraction counts whole days between the two
        # instants, which is what `.days` returns there.
        def days(today, timestamp)
          ((today.to_i - timestamp.to_i) / 86_400).floor
        end

        # Python's weekday() is Monday-based (Monday 0 … Sunday 6), while
        # Ruby's wday is Sunday-based, so the conversion happens here.
        def day_of_week(today) = (today.wday + 6) % 7

        def describe(days_no, today, timestamp)
          Time.at(timestamp).then do |then_time|
            case days_no
            when 0 then "Today"
            when 1 then "Yesterday"
            else describe_older(days_no, today, then_time)
            end
          end
        end

        def describe_older(days_no, today, then_time)
          if days_no <= day_of_week(today)
            then_time.strftime("%A")
          elsif days_no <= day_of_week(today) + 7
            "Last Week"
          else
            describe_months(days_no, today, then_time)
          end
        end

        def describe_months(days_no, today, then_time)
          if days_no <= today.day
            "This Month"
          elsif days_no <= today.day + 30
            "Last Month"
          else
            describe_years(days_no, today, then_time)
          end
        end

        def describe_years(days_no, today, then_time)
          if days_no < today.yday
            then_time.strftime("%B")
          elsif days_no <= today.yday + 365
            "Last Year"
          else
            then_time.strftime("%Y")
          end
        end
    end
  end
end
