#!/usr/bin/ruby
require "pry"
require "gst"

Gst.init

class Levelier
  attr_accessor :loop, :src, :level, :pipe
  def initialize
    @pipe = Gst::Pipeline.new
    @loop = GLib::MainLoop.new
    @src = Gst::ElementFactory.make("pulsesrc", "pulsey")
    @convert = Gst::ElementFactory.make("audioconvert")
    @src.client_name = "levelier"
    @level = Gst::ElementFactory.make("level")
    @spectrum = Gst::ElementFactory.make("spectrum")
    @spectrum.bands=100
    fakesink = Gst::ElementFactory.make "fakesink", "the_fakest_sink"
    @pipe.add(@src, @convert, @level, @spectrum, fakesink)
    caps = Gst::Caps.from_string("audio/x-raw,channels=1")
    @src >> @convert
    @convert.link_filtered(@level, caps)
    @level >> @spectrum >> fakesink
    
    @pipe.bus.add_watch do |bus, message|
      if message.type == "element"
        begin
        if message.has_name? "level"
          message.structure.get_value("decay").value
        elsif message.has_name? "spectrum"
          vals = message.structure.get_value("magnitude").value
          vals = vals[0..(@spectrum.bands/3).round]
          vals.map! do |val|
            if val<-40
              " 0"
            elsif val > 0
              "99"
            else
              val = (((val + 40.0)).floor).to_s.rjust(2)
            end
          end
          puts vals.join " "
        end
        rescue Exception => e
          binding.pry
        end
      end
      true
    end
    
    @level.interval=33333333
  end
  
  
  def run
    @pipe.play
    @loop.run
  end
end

lvl = Levelier.new


lvl.run
#binding.pry
