#!/bin/env ruby

require "rubygems"
require "bundler/setup"
Bundler.require

puts "Hello, #{ARGV[0] || 'World'}"

puts HTTP.get("https://ifconfig.me").to_s
