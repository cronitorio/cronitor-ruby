# frozen_string_literal: true

module Cronitor
  class Error < StandardError
  end

  class ValidationError < Error
  end

  class ConfigurationError < Error
  end

  class ErrorAppNotFound < Error
  end

  class ErrorGroupNotFound < Error
  end
end
