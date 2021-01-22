# frozen_string_literal: true

module Cronitor
  class Error < StandardError
  end

  class ValidationError < Error
  end

  class ConfigurationError < Error
  end
end
