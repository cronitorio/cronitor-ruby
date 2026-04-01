# frozen_string_literal: true

module Cronitor
  class Badge
    BADGE_API_URL = 'https://cronitor.io/api/badges'

    # Fetch all badges from the Cronitor API
    # Returns a hash where keys are tag names and values are Badge objects
    #
    # @param api_key [String] Optional API key (defaults to Cronitor.api_key)
    # @param api_version [String] Optional API version header
    # @return [Hash<String, Badge>] Hash of tag => Badge objects
    # @raise [Cronitor::Error] If API key is missing or API returns an error
    #
    # @example
    #   Cronitor.api_key = 'your-api-key'
    #   badges = Cronitor::Badge.all
    #   badges.each do |tag, badge|
    #     puts "#{tag}: #{badge.svg_url}"
    #     puts "Badge key: #{badge.key}"
    #   end
    def self.all(api_key: nil, api_version: nil)
      api_key ||= Cronitor.api_key

      unless api_key
        raise Error.new('No API key detected. Set Cronitor.api_key or pass api_key parameter')
      end

      headers = Monitor::Headers.json
      headers[:'Cronitor-Version'] = api_version if api_version

      resp = HTTParty.get(
        BADGE_API_URL,
        basic_auth: {
          username: api_key,
          password: ''
        },
        headers: headers,
        timeout: Cronitor.timeout || 10
      )

      case resp.code
      when 200
        data = JSON.parse(resp.body)
        badges = {}
        data.each do |tag, badge_data|
          badges[tag] = Badge.new(
            tag: tag,
            svg_url: badge_data['svg'],
            url: badge_data['url']
          )
        end
        badges
      else
        raise Error.new("Error fetching badges: #{resp.code} - #{resp.body}")
      end
    end

    attr_reader :tag, :svg_url, :url

    def initialize(tag:, svg_url: nil, url: nil)
      @tag = tag
      @svg_url = svg_url || url
      @url = url || svg_url
    end

    # Extract the badge key from the SVG URL
    # Badge URLs follow these patterns:
    #   Standard: https://cronitor.io/badges/ACCOUNT/production/KEY.svg
    #   Detailed: https://cronitor.io/badges/ACCOUNT/production/KEY/detailed.svg
    #
    # @return [String, nil] The badge key or nil if URL doesn't match expected pattern
    def key
      return nil unless svg_url

      # Match the key segment after /production/ - stops at next / or .
      match = svg_url.match(%r{/production/([^/.]+)})
      match&.[](1)
    end
  end
end
