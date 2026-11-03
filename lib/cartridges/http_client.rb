# frozen_string_literal: true

require "net/http"
require "json"
require "openssl"
require "socket"
require "uri"

module Cartridges
  # HttpError is what a non-2xx response raises, carrying the response so the
  # caller can read its status code and body.
  #
  # Stands in for requests.exceptions.HTTPError, which upstream's managers
  # name in their retryable_on lists.
  class HttpError < StandardError
    attr_reader :response

    def initialize(response)
      @response = response
      super("HTTP #{response.code} for #{response.uri}")
    end
  end

  # HttpClient is the port's replacement for the `requests` library upstream
  # depends on: a GET with a timeout, a status check, and JSON decoding.
  # The error classes the managers retry on are listed in RETRYABLE.
  module HttpClient
    # The errors upstream spells as HTTPError, SSLError and ConnectionError.
    RETRYABLE = [
      HttpError,
      OpenSSL::SSL::SSLError,
      SocketError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Net::OpenTimeout,
      Net::ReadTimeout,
    ].freeze

    # Response wraps Net::HTTPResponse with the three things the call sites
    # ask of it: the status code, the decoded JSON, and a status check.
    class Response
      attr_reader :uri, :raw

      def initialize(uri, raw)
        @uri = uri
        @raw = raw
      end

      def code = @raw.code.to_i
      def body = @raw.body
      def json = JSON.parse(body)
      def success? = (200..299).cover?(code)

      def raise_for_status!
        unless success?
          raise HttpError, self
        end

        self
      end
    end

    module_function

    def get(uri, headers: {}, timeout: 5)
      URI.parse(uri.to_s).then do |parsed|
        Response.new(parsed, request(parsed, headers, timeout))
      end
    end

    def request(parsed, headers, timeout)
      Net::HTTP.start(
        parsed.host,
        parsed.port,
        use_ssl: parsed.scheme == "https",
        open_timeout: timeout,
        read_timeout: timeout,
      ) { |http| http.request(Net::HTTP::Get.new(parsed, headers)) }
    end
  end
end
