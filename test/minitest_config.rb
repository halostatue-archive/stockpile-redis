# -*- ruby encoding: utf-8 -*-

gem 'minitest'
require 'minitest/autorun'
require 'minitest/pretty_diff'
require 'minitest/focus'
require 'minitest/moar'
require 'minitest/rerun'
require 'minitest/bisect'

require 'fakeredis'

module Minitest::FakeRedis
  def setup
    super
    Redis::Connection::Memory.reset_all_databases
  end

  Minitest::Test.send(:include, self)
end
