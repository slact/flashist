#!/usr/bin/ruby
require 'rubygems'
require 'bundler/setup'

require "optparse"
require 'ruby-conf'

opt = {
  config_file: "/etc/flashist/flashist.conf"
}

opt_parser = OptionParser.new do |opts|
  opts.on("-c", "--config PATH (#{opt[:config_file]})", "config file"){|v| opt[:config_file] = v}
end
opt_parser.parse!

load opt[:config_file]
$conf = RubyConf.flashist

while true do
  sleep 2
  #whatever?...
  
  
  
end
