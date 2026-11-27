# frozen_string_literal: true

module Cronitor
  module ErrorTrackingAPI
    API_BASE_URL = 'https://cronitor.io'

    class << self
      def require_api_key(api_key)
        key = api_key || Cronitor.api_key
        unless key && !key.to_s.empty?
          raise Error.new('No API key detected. Set Cronitor.api_key or pass api_key parameter')
        end

        key
      end

      def headers(api_version: nil, json_body: false)
        result = { 'User-Agent' => "cronitor-ruby-#{Cronitor::VERSION}" }
        result['Content-Type'] = 'application/json' if json_body
        version = api_version || Cronitor.api_version
        result['Cronitor-Version'] = version if version
        result
      end

      def raise_for_error(resp, not_found_class: nil, not_found_msg: nil)
        return if resp.code >= 200 && resp.code < 300
        raise ValidationError.new(resp.body) if [400, 422].include?(resp.code)
        raise not_found_class.new(not_found_msg) if resp.code == 404 && not_found_class

        raise Error.new("Unexpected error #{resp.code}: #{resp.body}")
      end

      def parse_json(body)
        return body if body.is_a?(Hash) || body.is_a?(Array)

        JSON.parse(body.to_s)
      end

      def extract_list(body, keys)
        return body if body.is_a?(Array)

        if body.is_a?(Hash)
          keys.each do |key|
            return body[key] if body[key].is_a?(Array)
          end
        end
        []
      end

      def positive_page_size?(page_size)
        return false unless page_size.is_a?(Numeric) && page_size.real?
        return false if page_size.respond_to?(:finite?) && !page_size.finite?

        page_size.to_i.positive?
      end

      def normalize_page_size(page_size)
        positive_page_size?(page_size) ? page_size.to_i : 50
      end

      def request_timeout
        Cronitor.timeout || 10
      end
    end
  end

  class ErrorApp
    attr_reader :key, :api_key

    def self.api_url(key = nil)
      base = "#{ErrorTrackingAPI::API_BASE_URL}/api/error-apps"
      key ? "#{base}/#{key}" : base
    end

    def self.create(name:, api_key: nil, **extra)
      auth_key = ErrorTrackingAPI.require_api_key(api_key)
      payload = extra.merge(name: name)
      resp = HTTParty.post(
        api_url,
        basic_auth: { username: auth_key, password: '' },
        body: payload.to_json,
        headers: ErrorTrackingAPI.headers(json_body: true),
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(resp)
      data = ErrorTrackingAPI.parse_json(resp.body)
      app = new(data['key'], api_key: api_key)
      app.data = data
      app
    end

    def self.list(page: 1, page_size: 50, auto_paginate: false, api_key: nil)
      apps = []
      current_page = page
      valid_page_size = ErrorTrackingAPI.positive_page_size?(page_size)
      size = ErrorTrackingAPI.normalize_page_size(page_size)

      loop do
        result = fetch_page(current_page, size, api_key: api_key)
        apps.concat(result)
        break if !auto_paginate || !valid_page_size || result.length < size

        current_page += 1
      end
      apps
    end

    def self.fetch_page(page, page_size, api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key)
      resp = HTTParty.get(
        api_url,
        basic_auth: { username: auth_key, password: '' },
        query: { page: page, pageSize: page_size },
        headers: ErrorTrackingAPI.headers,
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(resp)
      items = ErrorTrackingAPI.extract_list(ErrorTrackingAPI.parse_json(resp.body), %w[error_apps apps data])
      items.map do |item|
        app = new(item['key'], api_key: api_key)
        app.data = item
        app
      end
    end
    private_class_method :fetch_page

    def initialize(key, api_key: nil)
      @key = key
      @api_key = api_key || Cronitor.api_key
    end

    def data
      return @data if defined?(@data) && !@data.nil?

      @data = Cronitor.symbolize_keys(fetch)
      @data
    end

    def data=(value)
      @data = value.nil? ? nil : Cronitor.symbolize_keys(value)
    end

    def dsn
      data[:dsn]
    end

    def name
      data[:name]
    end

    def update(name: nil, api_key: nil, **extra)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      payload = extra.dup
      payload[:name] = name unless name.nil?
      resp = HTTParty.patch(
        self.class.api_url(key),
        basic_auth: { username: auth_key, password: '' },
        body: payload.to_json,
        headers: ErrorTrackingAPI.headers(json_body: true),
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorAppNotFound,
        not_found_msg: "ErrorApp '#{key}' not found"
      )
      self.data = ErrorTrackingAPI.parse_json(resp.body)
      self
    end

    def delete(api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      resp = HTTParty.delete(
        self.class.api_url(key),
        basic_auth: { username: auth_key, password: '' },
        headers: ErrorTrackingAPI.headers,
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorAppNotFound,
        not_found_msg: "ErrorApp '#{key}' not found"
      )
      true
    end

    def rotate_key(api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      resp = HTTParty.post(
        "#{self.class.api_url(key)}/rotate-key",
        basic_auth: { username: auth_key, password: '' },
        headers: ErrorTrackingAPI.headers(json_body: true),
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorAppNotFound,
        not_found_msg: "ErrorApp '#{key}' not found"
      )
      self.data = ErrorTrackingAPI.parse_json(resp.body)
      self
    end

    private

    def fetch(api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      resp = HTTParty.get(
        self.class.api_url(key),
        basic_auth: { username: auth_key, password: '' },
        headers: ErrorTrackingAPI.headers(json_body: true),
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorAppNotFound,
        not_found_msg: "ErrorApp '#{key}' not found"
      )
      ErrorTrackingAPI.parse_json(resp.body)
    end
  end

  class ErrorGroup
    attr_reader :key, :api_key

    def self.api_url(key = nil)
      base = "#{ErrorTrackingAPI::API_BASE_URL}/api/errors"
      key ? "#{base}/#{key}" : base
    end

    def self.list(app: nil, env: nil, status: nil, level: nil, start: nil, q: nil,
                  order_by: nil, page: 1, page_size: 50, auto_paginate: false, api_key: nil, **opts)
      filters = {}
      end_time = opts[:end]
      resolved_order_by = order_by || opts[:orderBy]

      [
        ['app', app],
        ['env', env],
        ['status', status],
        ['level', level],
        ['start', start],
        ['end', end_time],
        ['q', q],
        ['orderBy', resolved_order_by]
      ].each do |param_name, value|
        filters[param_name] = value unless value.nil?
      end

      groups = []
      current_page = page
      valid_page_size = ErrorTrackingAPI.positive_page_size?(page_size)
      size = ErrorTrackingAPI.normalize_page_size(page_size)

      loop do
        result = fetch_page(current_page, size, filters: filters, api_key: api_key)
        groups.concat(result)
        break if !auto_paginate || !valid_page_size || result.length < size

        current_page += 1
      end
      groups
    end

    def self.fetch_page(page, page_size, filters: {}, api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key)
      params = filters.merge('page' => page, 'pageSize' => page_size)
      resp = HTTParty.get(
        api_url,
        basic_auth: { username: auth_key, password: '' },
        query: params,
        headers: ErrorTrackingAPI.headers,
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(resp)
      items = ErrorTrackingAPI.extract_list(ErrorTrackingAPI.parse_json(resp.body), %w[errors data groups])
      items.map do |item|
        group = new(item['key'], api_key: api_key)
        group.data = item
        group
      end
    end
    private_class_method :fetch_page

    def initialize(key, api_key: nil)
      @key = key
      @api_key = api_key || Cronitor.api_key
    end

    def data
      return @data if defined?(@data) && !@data.nil?

      @data = Cronitor.symbolize_keys(fetch)
      @data
    end

    def data=(value)
      @data = value.nil? ? nil : Cronitor.symbolize_keys(value)
    end

    def update(status:, env: nil, api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      payload = { status: status }
      payload[:env] = env unless env.nil?
      resp = HTTParty.patch(
        self.class.api_url(key),
        basic_auth: { username: auth_key, password: '' },
        body: payload.to_json,
        headers: ErrorTrackingAPI.headers(json_body: true),
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorGroupNotFound,
        not_found_msg: "ErrorGroup '#{key}' not found"
      )
      self.data = ErrorTrackingAPI.parse_json(resp.body)
      self
    end

    def events(env: nil, app: nil, cursor: nil, limit: 50, api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      params = { 'limit' => limit }
      params['env'] = env unless env.nil?
      params['app'] = app unless app.nil?
      params['cursor'] = cursor unless cursor.nil?

      resp = HTTParty.get(
        "#{self.class.api_url(key)}/events",
        basic_auth: { username: auth_key, password: '' },
        query: params,
        headers: ErrorTrackingAPI.headers,
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorGroupNotFound,
        not_found_msg: "ErrorGroup '#{key}' not found"
      )
      ErrorTrackingAPI.parse_json(resp.body)
    end

    def event(event_id, api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      resp = HTTParty.get(
        "#{self.class.api_url(key)}/events/#{event_id}",
        basic_auth: { username: auth_key, password: '' },
        headers: ErrorTrackingAPI.headers,
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorGroupNotFound,
        not_found_msg: "Error event '#{event_id}' not found"
      )
      ErrorTrackingAPI.parse_json(resp.body)
    end

    private

    def fetch(api_key: nil)
      auth_key = ErrorTrackingAPI.require_api_key(api_key || @api_key)
      resp = HTTParty.get(
        self.class.api_url(key),
        basic_auth: { username: auth_key, password: '' },
        headers: ErrorTrackingAPI.headers(json_body: true),
        timeout: ErrorTrackingAPI.request_timeout
      )
      ErrorTrackingAPI.raise_for_error(
        resp,
        not_found_class: ErrorGroupNotFound,
        not_found_msg: "ErrorGroup '#{key}' not found"
      )
      ErrorTrackingAPI.parse_json(resp.body)
    end
  end
end
