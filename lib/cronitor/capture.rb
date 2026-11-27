# frozen_string_literal: true

require 'English'
require 'rbconfig'
require 'securerandom'
require 'socket'

module Cronitor
  module Capture
    MONITOR_TAG = 'cronitor.monitor'
    SERIES_TAG = 'cronitor.series'

    MAX_VALUE_LENGTH = 4000
    MAX_MESSAGE_LENGTH = 4000
    MAX_TAGS = 50
    MAX_TAG_KEY_LENGTH = 64
    MAX_TAG_VALUE_LENGTH = 400
    MAX_CHAINED_EXCEPTIONS = 10
    MAX_FRAMES = 100
    MAX_LINE_LENGTH = 1000
    CONTEXT_LINES = 5

    EVENT_LEVELS = {
      'fatal' => 'fatal',
      'critical' => 'fatal',
      'error' => 'error',
      'warning' => 'warning',
      'warn' => 'warning',
      'info' => 'info',
      'debug' => 'debug'
    }.freeze

    BACKTRACE_RE = /\A(.+?):(\d+)(?::in [`'](.+?)')?\z/.freeze
    THREAD_JOB_KEY = :cronitor_current_job

    JobContext = Struct.new(:monitor, :series, :env)

    class << self
      def current_job
        Thread.current[THREAD_JOB_KEY]
      end

      def bind_job(monitor, series, env)
        previous = Thread.current[THREAD_JOB_KEY]
        Thread.current[THREAD_JOB_KEY] = JobContext.new(monitor, series, env)
        previous
      end

      def unbind_job(token)
        Thread.current[THREAD_JOB_KEY] = token
      end

      def capture_exception(exception = nil, monitor: nil, series: nil, level: 'error',
                            tags: nil, extra: nil, fingerprint: nil)
        _capture_exception(
          exception,
          monitor: monitor,
          series: series,
          level: level,
          tags: tags,
          extra: extra,
          fingerprint: fingerprint
        )
      end

      def capture_message(message, level: 'info', monitor: nil, series: nil,
                          tags: nil, extra: nil, fingerprint: nil)
        _capture_message(
          message,
          level: level,
          monitor: monitor,
          series: series,
          tags: tags,
          extra: extra,
          fingerprint: fingerprint
        )
      end

      def _capture_exception(exception, monitor: nil, series: nil, level: 'error', tags: nil, extra: nil,
                             fingerprint: nil, env: nil, mechanism: 'generic', handled: true)
        exc = resolve_exception(exception)
        return nil if exc.nil?

        event = base_event(level, monitor, series, tags, extra, fingerprint, env)
        event['exception'] = { 'values' => exception_values(exc, mechanism, handled) }
        submit_event(event)
      rescue StandardError => e
        Cronitor.logger&.warn("Cronitor could not capture an exception: #{e}")
        nil
      end

      def _capture_message(message, level: 'info', monitor: nil, series: nil, tags: nil, extra: nil,
                           fingerprint: nil, env: nil)
        event = base_event(level, monitor, series, tags, extra, fingerprint, env)
        event['message'] = { 'formatted' => truncate(safe_str(message), MAX_MESSAGE_LENGTH) }
        submit_event(event)
      rescue StandardError => e
        Cronitor.logger&.warn("Cronitor could not capture a message: #{e}")
        nil
      end

      private

      def submit_event(event)
        Ingest.submit_event(event) ? event['event_id'] : nil
      end

      def resolve_exception(exception)
        exc = exception.nil? ? $ERROR_INFO : exception
        return nil if exc.nil?

        unless exc.is_a?(Exception)
          Cronitor.logger&.warn("Cronitor capture_exception expects an Exception, got #{exc.class.name}")
          return nil
        end

        exc
      end

      def resolve_binding(monitor, series, env)
        job = current_job
        if job && (monitor.nil? || monitor == job.monitor)
          monitor = job.monitor
          series = job.series if series.nil?
          env = job.env if env.nil?
        end
        [monitor, series, env || Cronitor.environment]
      end

      def base_event(level, monitor, series, tags, extra, fingerprint, env)
        user_tags = tags.is_a?(Hash) ? tags.dup : {}
        monitor = user_tags[MONITOR_TAG] || user_tags[MONITOR_TAG.to_sym] if monitor.nil?
        series = user_tags[SERIES_TAG] || user_tags[SERIES_TAG.to_sym] if series.nil?
        monitor, series, env = resolve_binding(monitor, series, env)

        bound = {}
        bound[MONITOR_TAG] = monitor unless monitor.nil?
        bound[SERIES_TAG] = series unless series.nil?

        event_tags = {}
        (bound.to_a + user_tags.to_a).each do |key, value|
          tag_key = truncate(safe_str(key), MAX_TAG_KEY_LENGTH)
          next if event_tags.key?(tag_key) || event_tags.length >= MAX_TAGS

          event_tags[tag_key] = truncate(safe_str(value), MAX_TAG_VALUE_LENGTH)
        end

        event = {
          'event_id' => SecureRandom.hex(16),
          'timestamp' => Ingest.format_timestamp,
          'platform' => 'ruby',
          'level' => EVENT_LEVELS.fetch(safe_str(level).downcase, 'error'),
          'server_name' => hostname,
          'tags' => event_tags,
          'extra' => extra.is_a?(Hash) ? extra.dup : {},
          'sdk' => Ingest.sdk_info
        }

        unless fingerprint.nil?
          event['fingerprint'] = if fingerprint.is_a?(String)
                                   [fingerprint]
                                 else
                                   Array(fingerprint).map { |part| safe_str(part) }
                                 end
        end

        event['release'] = safe_str(Cronitor.release) if Cronitor.release && !Cronitor.release.to_s.empty?
        event['environment'] = safe_str(env) if env && !env.to_s.empty?
        event
      end

      def walk_chain(exception)
        chain = []
        seen = {}.compare_by_identity
        current = exception
        while current.is_a?(Exception) && !seen[current] && chain.length < MAX_CHAINED_EXCEPTIONS
          chain << current
          seen[current] = true
          current = current.respond_to?(:cause) ? current.cause : nil
        end
        chain.reverse
      end

      def exception_values(exception, mechanism, handled)
        walk_chain(exception).map do |exc|
          type_name = exc.class.name || safe_str(exc.class)
          {
            'type' => type_name,
            'value' => truncate(safe_str(exc.message), MAX_VALUE_LENGTH),
            'module' => type_module(type_name),
            'mechanism' => { 'type' => mechanism, 'handled' => handled },
            'stacktrace' => { 'frames' => parse_frames(exc.backtrace) }
          }
        end
      end

      def type_module(type_name)
        return nil unless type_name.include?('::')

        idx = type_name.rindex('::')
        type_name[0...idx]
      end

      def parse_frames(backtrace)
        return [] unless backtrace.is_a?(Array) && !backtrace.empty?

        entries = backtrace.reverse
        if entries.length > MAX_FRAMES
          half = MAX_FRAMES / 2
          entries = entries[0, half] + entries[-half, half]
        end
        entries.map { |line| parse_frame(line) }
      end

      def parse_frame(line)
        str = safe_str(line)
        match = BACKTRACE_RE.match(str)
        if match
          raw_path = match[1]
          lineno = match[2].to_i
          function = match[3] || '<main>'
        else
          raw_path = str
          lineno = nil
          function = '<unknown>'
        end

        abs_path = raw_path.start_with?('<', '(') ? raw_path : File.expand_path(raw_path)
        pre_context, context_line, post_context = source_context(abs_path, lineno)
        {
          'filename' => raw_path,
          'abs_path' => abs_path,
          'function' => function,
          'lineno' => lineno,
          'context_line' => context_line,
          'pre_context' => pre_context,
          'post_context' => post_context,
          'in_app' => in_app?(abs_path)
        }
      end

      def source_context(abs_path, lineno)
        return [[], nil, []] if lineno.nil? || lineno < 1 || abs_path.start_with?('<', '(')
        return [[], nil, []] unless File.file?(abs_path) && File.readable?(abs_path)

        lines = File.readlines(abs_path)
        return [[], nil, []] if lines.empty? || lineno > lines.length

        index = lineno - 1
        start_idx = [0, index - CONTEXT_LINES].max
        end_idx = [lines.length - 1, index + CONTEXT_LINES].min
        window = lines[start_idx..end_idx].map do |l|
          truncate(l.chomp, MAX_LINE_LENGTH)
        end
        offset = index - start_idx
        pre = offset.positive? ? window[0...offset] : []
        post = (offset + 1) < window.length ? window[(offset + 1)..-1] : []
        [pre, window[offset], post]
      rescue StandardError
        [[], nil, []]
      end

      def library_prefixes
        @library_prefixes ||= begin
          candidates = [
            RbConfig::CONFIG['rubylibdir'],
            RbConfig::CONFIG['archdir'],
            RbConfig::CONFIG['sitelibdir'],
            RbConfig::CONFIG['vendorlibdir'],
            File.expand_path('..', __dir__)
          ]
          candidates.concat(Gem.path) if defined?(Gem) && Gem.respond_to?(:path)

          prefixes = []
          candidates.compact.each do |path|
            next if path.empty?

            expanded = File.expand_path(path).chomp(File::SEPARATOR) + File::SEPARATOR
            prefixes << expanded
            begin
              real = File.realpath(path).chomp(File::SEPARATOR) + File::SEPARATOR
              prefixes << real
            rescue StandardError
              nil
            end
          end
          prefixes.uniq
        end
      end

      def in_app?(abs_path)
        return false if abs_path.start_with?('<internal:')
        return true if abs_path.start_with?('<', '(')
        return false if abs_path.include?('/gems/') || abs_path.include?('/bundler/')

        library_prefixes.none? { |prefix| abs_path.start_with?(prefix) }
      end

      def hostname
        Socket.gethostname
      rescue StandardError
        ''
      end

      def truncate(value, length)
        value.length <= length ? value : value[0, length]
      end

      def safe_str(value)
        return value if value.is_a?(String)

        value.to_s
      rescue StandardError
        begin
          value.inspect
        rescue StandardError
          "<unrepresentable #{value.class.name}>"
        end
      end
    end
  end
end
