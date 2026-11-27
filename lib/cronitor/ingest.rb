# frozen_string_literal: true

require 'json'
require 'stringio'
require 'uri'
require 'zlib'

module Cronitor
  module Ingest
    SDK_NAME = 'cronitor-ruby'
    MAX_QUEUE_SIZE = 1000
    SEND_TIMEOUT = 5
    MAX_RETRY_AFTER = 60.0
    ATEXIT_FLUSH_TIMEOUT = 2.0
    MAX_EVENT_BYTES = 900 * 1024
    TRIMMED_FRAMES = 20
    EVENT_CONTENT_TYPE = 'application/json'

    @start_lock = Mutex.new
    @atexit_registered = false

    class << self
      def parse_dsn(dsn)
        return nil unless dsn.is_a?(String)

        raw = dsn.strip
        return nil if raw.empty?

        parsed = URI.parse(raw)
        return nil unless %w[http https].include?(parsed.scheme)
        return nil if parsed.host.nil? || parsed.host.empty?
        return nil if parsed.user.nil? || parsed.user.empty?

        host = parsed.host
        host = "[#{host}]" if host.include?(':') && !host.start_with?('[')
        explicit_port = parsed.port && parsed.port != parsed.default_port
        netloc = explicit_port ? "#{host}:#{parsed.port}" : host

        path = parsed.path.to_s.sub(%r{\A/+}, '').sub(%r{/+\z}, '')
        if path.empty?
          prefix = ''
          project_id = '1'
        elsif path.include?('/')
          idx = path.rindex('/')
          prefix = "/#{path[0...idx]}"
          project_id = path[(idx + 1)..-1]
        else
          prefix = ''
          project_id = path
        end

        url = "#{parsed.scheme}://#{netloc}#{prefix}/api/#{project_id}/envelope/"
        public_dsn = "#{parsed.scheme}://#{parsed.user}@#{netloc}#{prefix}/#{project_id}"
        [parsed.user, url, public_dsn]
      rescue URI::InvalidURIError, ArgumentError
        nil
      end

      def sdk_info
        { 'name' => SDK_NAME, 'version' => Cronitor::VERSION }
      end

      def auth_header(ingest_key)
        "Sentry sentry_key=#{ingest_key}, sentry_version=7, sentry_client=#{SDK_NAME}/#{Cronitor::VERSION}"
      end

      def request_headers(ingest_key)
        {
          'Content-Type' => 'application/x-sentry-envelope',
          'Content-Encoding' => 'gzip',
          'User-Agent' => SDK_NAME,
          'X-Sentry-Auth' => auth_header(ingest_key)
        }
      end

      def format_timestamp(value = nil)
        (value || Time.now).utc.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')
      end

      def json_bytes(obj)
        text = JSON.generate(json_safe(obj))
        text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').b
      end

      def serialize_envelope(headers, items)
        parts = [json_bytes(headers), "\n".b]
        items.each do |item_headers, payload|
          payload_bytes = payload.b
          merged = item_headers.merge('length' => payload_bytes.bytesize)
          parts << json_bytes(merged) << "\n".b << payload_bytes << "\n".b
        end
        parts.join
      end

      def gzip_bytes(data)
        io = StringIO.new(''.b)
        gz = Zlib::GzipWriter.new(io, 6)
        gz.write(data)
        gz.close
        io.string
      end

      def event_bytes(event)
        payload = json_bytes(event)
        return payload if payload.bytesize <= MAX_EVENT_BYTES

        begin
          copy = event.dup
          dropped = []
          event_trims.each do |note, trim_fn|
            next unless trim_fn.call(copy)

            dropped << note
            extra = copy['extra'].is_a?(Hash) ? copy['extra'].dup : {}
            extra['_trimmed'] = "#{dropped.join('; ')}: event over #{MAX_EVENT_BYTES / 1024} KB"
            copy['extra'] = extra
            payload = json_bytes(copy)
            break if payload.bytesize <= MAX_EVENT_BYTES
          end
        rescue StandardError => e
          Cronitor.logger&.warn("Cronitor could not trim an oversized event: #{e}")
        end
        payload
      end

      def event_envelope(payload, event_id, sent_at: nil, dsn: nil)
        headers = {
          'event_id' => event_id,
          'sent_at' => format_timestamp(sent_at),
          'sdk' => sdk_info
        }
        headers['dsn'] = dsn if dsn && !dsn.empty?
        item = { 'type' => 'event', 'content_type' => EVENT_CONTENT_TYPE }
        serialize_envelope(headers, [[item, payload]])
      end

      def get_transport
        @transport ||= Transport.new
      end

      def set_transport(transport)
        previous = get_transport
        @transport = transport
        previous
      end

      def submit_event(event, dsn: nil)
        get_transport.submit_event(event, dsn: dsn)
      end

      def flush(timeout: 2.0)
        get_transport.flush(timeout: timeout)
      rescue StandardError => e
        Cronitor.logger&.warn("Cronitor flush failed: #{e}")
        false
      end

      attr_reader :start_lock

      def register_atexit
        return if @atexit_registered

        @atexit_registered = true
        at_exit { flush(timeout: ATEXIT_FLUSH_TIMEOUT) }
      end

      private

      def json_safe(value, depth = 0, seen = {}.compare_by_identity)
        case value
        when Float
          value.finite? ? value : value.to_s
        when String
          scrub_utf8(value)
        when Integer, TrueClass, FalseClass, NilClass
          value
        when Hash
          return safe_inspect(value) if depth >= 10 || seen[value]

          next_seen = seen.dup
          next_seen[value] = true
          result = {}
          value.each do |k, v|
            result[scrub_utf8(k.to_s)] = json_safe(v, depth + 1, next_seen)
          end
          result
        when Array
          return safe_inspect(value) if depth >= 10 || seen[value]

          next_seen = seen.dup
          next_seen[value] = true
          value.map { |item| json_safe(item, depth + 1, next_seen) }
        else
          scrub_utf8(safe_inspect(value))
        end
      end

      def scrub_utf8(str)
        str.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
      rescue StandardError
        str.to_s.b.encode('UTF-8', 'BINARY', invalid: :replace, undef: :replace, replace: '?')
      end

      def safe_inspect(value)
        value.is_a?(Symbol) ? value.to_s : value.inspect
      rescue StandardError
        "<unrepresentable #{value.class.name}>"
      end

      def own_frames(event)
        exception = event['exception']
        return [] unless exception.is_a?(Hash)

        raw_values = exception['values']
        return [] unless raw_values.is_a?(Array)

        values = []
        frame_lists = []
        raw_values.each do |val|
          next unless val.is_a?(Hash)

          stacktrace = val['stacktrace']
          if stacktrace.is_a?(Hash) && stacktrace['frames'].is_a?(Array) && !stacktrace['frames'].empty?
            frames = stacktrace['frames'].map { |f| f.is_a?(Hash) ? f.dup : f }
            val_copy = val.merge('stacktrace' => stacktrace.merge('frames' => frames))
            values << val_copy
            frame_lists << frames
          else
            values << val
          end
        end
        event['exception'] = exception.merge('values' => values) unless values.empty?
        frame_lists
      end

      def drop_source_context(event)
        dropped = false
        own_frames(event).each do |frames|
          frames.each do |frame|
            next unless frame.is_a?(Hash)

            %w[pre_context post_context].each do |key|
              if frame.key?(key)
                frame.delete(key)
                dropped = true
              end
            end
          end
        end
        dropped
      end

      def drop_extra(event)
        extra = event['extra']
        return false unless extra.is_a?(Hash)
        return false if extra.keys.all? { |k| k == '_trimmed' }

        event['extra'] = {}
        true
      end

      def keep_last_frames(event)
        cut = false
        own_frames(event).each do |frames|
          if frames.length > TRIMMED_FRAMES
            frames.slice!(0, frames.length - TRIMMED_FRAMES)
            cut = true
          end
        end
        cut
      end

      def event_trims
        [
          ['source context dropped', method(:drop_source_context)],
          ['extra dropped', method(:drop_extra)],
          ["frames cut to the last #{TRIMMED_FRAMES} per exception", method(:keep_last_frames)]
        ]
      end
    end

    class FlushSignal
      def initialize
        @mutex = Mutex.new
        @cond = ConditionVariable.new
        @done = false
      end

      def signal
        @mutex.synchronize do
          @done = true
          @cond.broadcast
        end
      end

      def wait(timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
        @mutex.synchronize do
          until @done
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return false if remaining <= 0

            @cond.wait(@mutex, remaining)
          end
          true
        end
      end
    end

    class Transport
      attr_reader :dropped

      def initialize(send: nil, maxsize: MAX_QUEUE_SIZE)
        @send = send || method(:http_send)
        @maxsize = maxsize
        @queue = nil
        @thread = nil
        @pid = nil
        @rate_limited_until = 0.0
        @reported_rate_limit = false
        @reported_missing_dsn = false
        @reported_invalid_dsn = false
        @dropped = 0
      end

      def submit_event(event, dsn: nil)
        resolved = resolve_dsn(dsn)
        return false if resolved.nil?

        ingest_key, url, public_dsn = resolved
        enqueue([:event, url, ingest_key, public_dsn, event['event_id'], Ingest.event_bytes(event)])
      end

      def flush(timeout: 2.0)
        return true if @thread.nil? || @pid != Process.pid || !@thread.alive?

        deadline = monotonic_now + timeout.to_f
        signal = FlushSignal.new
        return false unless enqueue_with_timeout([:flush, signal], deadline)

        remaining = [0.0, deadline - monotonic_now].max
        signal.wait(remaining)
      end

      private

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def resolve_dsn(dsn)
        raw = dsn.nil? ? Cronitor.dsn : dsn
        if raw.nil? || (raw.is_a?(String) && raw.strip.empty?)
          unless @reported_missing_dsn
            @reported_missing_dsn = true
            Cronitor.logger&.error(
              'No DSN detected. Set Cronitor.dsn or CRONITOR_DSN to capture exceptions and messages.'
            )
          end
          return nil
        end

        parsed = Ingest.parse_dsn(raw)
        if parsed.nil?
          unless @reported_invalid_dsn
            @reported_invalid_dsn = true
            Cronitor.logger&.error('Invalid Cronitor DSN. Expected https://<ingest_key>@cronitor.link/1.')
          end
          return nil
        end

        parsed
      end

      def enqueue(item)
        ensure_worker
        @queue.push(item, true)
        true
      rescue ThreadError
        @dropped += 1
        if @dropped == 1 || (@dropped % 1000).zero?
          Cronitor.logger&.warn("Cronitor ingest queue is full, #{@dropped} item(s) dropped so far.")
        end
        false
      rescue StandardError => e
        Cronitor.logger&.warn("Cronitor could not queue an item: #{e}")
        false
      end

      def enqueue_with_timeout(item, deadline)
        loop do
          @queue.push(item, true)
          return true
        rescue ThreadError
          return false if monotonic_now >= deadline

          sleep(0.01)
        end
      end

      def ensure_worker
        pid = Process.pid
        return if @pid == pid && @thread && @thread.alive?

        Ingest.start_lock.synchronize do
          return if @pid == pid && @thread && @thread.alive?

          @queue = SizedQueue.new(@maxsize) if @pid != pid || @queue.nil?
          @rate_limited_until = 0.0 if @pid != pid

          queue = @queue
          @thread = Thread.new { run_worker(queue) }
          @pid = pid
        end
        Ingest.register_atexit
      end

      def run_worker(queue)
        loop do
          item = queue.pop
          begin
            case item[0]
            when :event
              _, url, ingest_key, public_dsn, event_id, payload = item
              envelope = Ingest.event_envelope(payload, event_id, dsn: public_dsn)
              deliver(url, ingest_key, envelope)
            when :flush
              item[1].signal
            end
          rescue StandardError => e
            Cronitor.logger&.warn("Cronitor could not send an envelope: #{e}")
          end
        end
      end

      def deliver(url, ingest_key, body, count = 1)
        left = @rate_limited_until - monotonic_now
        if left.positive?
          @dropped += count
          unless @reported_rate_limit
            @reported_rate_limit = true
            Cronitor.logger&.warn(
              format('Cronitor is rate limited for %.0f more seconds; dropping envelopes until then.', left)
            )
          end
          return
        end

        begin
          response = @send.call(url, Ingest.gzip_bytes(body), Ingest.request_headers(ingest_key), SEND_TIMEOUT)
        rescue StandardError => e
          Cronitor.logger&.warn("Cronitor could not send an envelope to #{url}: #{e}")
          return
        end

        status = response.respond_to?(:code) ? response.code : nil
        return unless status.is_a?(Integer)

        if status == 429
          delay = retry_after(response)
          @rate_limited_until = monotonic_now + delay
          @reported_rate_limit = false
          Cronitor.logger&.warn(
            format('Cronitor rate limited the envelope (HTTP 429); not sending for %.0f seconds.', delay)
          )
        elsif status >= 400
          Cronitor.logger&.warn("Cronitor rejected an envelope with HTTP #{status}.")
        end
      end

      def retry_after(response)
        headers = response.respond_to?(:headers) && response.headers ? response.headers : {}
        delay = nil
        limits = header_value(headers, 'X-Sentry-Rate-Limits')
        delay = parse_seconds(limits.split(',').first.to_s.split(':').first) if limits
        delay = parse_seconds(header_value(headers, 'Retry-After')) if delay.nil?
        delay = MAX_RETRY_AFTER if delay.nil?
        delay.clamp(0.0, MAX_RETRY_AFTER)
      end

      def header_value(headers, name)
        target = name.downcase
        headers.each do |k, v|
          return v.to_s if k.to_s.downcase == target
        end
        nil
      end

      def parse_seconds(value)
        return nil if value.nil?

        seconds = Float(value)
        seconds.finite? ? seconds : nil
      rescue ArgumentError, TypeError
        nil
      end

      def http_send(url, data, headers, timeout)
        HTTParty.post(
          url,
          body: data,
          headers: headers,
          timeout: timeout,
          format: :plain
        )
      end
    end
  end
end
