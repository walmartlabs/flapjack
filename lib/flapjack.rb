#!/usr/bin/env ruby

require 'oj'

module Flapjack

  DEFAULT_INITIAL_FAILURE_DELAY = 30
  DEFAULT_REPEAT_FAILURE_DELAY  = 60

  def self.load_json(data)
    Oj.load(data, :mode => :strict, :symbol_keys => false)
  end

  def self.dump_json(data)
    Oj.dump(data, :mode => :compat, :time_format => :ruby, :indent => 0)
  end

  def self.sanitize(str)
    return str if str.nil? || !str.is_a?(String) || str.valid_encoding?
    return str.scrub('?') if str.respond_to(:scrub)
    str.chars.collect {|c| c.valid_encoding? ? c : '_' }.join
  end

end

