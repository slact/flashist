#!/usr/bin/ruby
require 'rubygems'
require 'bundler/setup'
require "celluloid"
require "celluloid/current"
require "hidapi"
require "erb"

require "json"

require 'reel/rack'
require "color"


require "pry"

class HIDAPI::Device
  def kill_read_thread
    @thread.kill
    self.shutdown_thread = true
  end
  public :mutex
end

class Flashist #don't punch me bro@cava
  def initialize
    init_device
  end
  
  def init_device
    #puts "init device"
    begin
      @dev = HIDAPI::open(0x16c0, 0x0486)
    rescue Exception => e
      puts "device not found"
    end
    if @dev
      @dev.kill_read_thread
      #puts "device connected"
    end
  end
  
  def send_raw(*args)
    #puts "send raw"
    init_device unless @dev
    begin
      @dev.write(*args) if @dev
    rescue LIBUSB::ERROR_BUSY => e
      puts "write failed, device busy. don't worry about it though"
    rescue Exception => e
      puts "device write failed, exception #{e}"
      sleep 0.1
      puts "gonna close and reopen"
      @dev.close
      sleep 0.1
      @dev = nil
      puts "done device failed #{@dev}"
    end
  end
  
  def send_rgb(rgb)
    send_raw(42, (rgb.r*255).to_i, (rgb.g*255).to_i, (rgb.b*255).to_i)
  end
  def send_hello
    send_raw ">"
  end
end

class SpectrumToRGB
  attr_accessor :colordrift, :colorscale, :peaks_measure_count, :redblue_shift
  
  def initialize
    @offset = 0
    
    @peaks_measure_count = 10
    @colordrift = 0.01
    @colorscale = 1.5
    @redblue_shift = 0
    @floor = 2
  end
  
  def get_info
    {
      peaks_measure_count: @peaks_measure_count,
      colorscale: @colorscale,
      colordrift: @colordrift,
      redblue_shift: @redblue_shift
    }
  end
  
  def spectral_center_of_mass(bars)
    
    m = 0
    volsum = 0
    bars.each_with_index do |val, i|
      vv= val
      m += (i * vv)
      volsum += vv
    end
    
    sorted_bars = bars.sort.reverse
    
    max_sum = sorted_bars[0...@peaks_measure_count].sum
    
    m = m.to_f/volsum
    m = m/bars.count
    
    @offset = @offset + @colordrift % 1
    
    h = ((m*@colorscale + @offset)*360) % 360
    h = 0 if h.nan?
    
    s = 0.8
    l = max_sum.to_f / (@peaks_measure_count * 4096)
    
    #puts [h.to_i, s, l.round(5)].to_s
    
    hsl = Color::HSL.new(h,s*100,l*100)
    rgb = hsl.to_rgb
    
    if rgb.frozen? && @redblue_shift
      rgb = Color::RGB.new(rgb.r, rgb.g, rgb.b)
    end
    
    if @floor > 0
      rgb.r += (@floor.to_f/255)
      rgb.g += (@floor.to_f/255)
      rgb.b += (@floor.to_f/255)
    end
    
    if @redblue_shift > 0
      swap = rgb.b * @redblue_shift.abs
      rgb.b -= swap
      rgb.r += swap
    elsif @redblue_shift < 0
      swap = rgb.r * @redblue_shift.abs
      rgb.r -= swap
      rgb.b += swap
    end
    
    return rgb
  end
end


class CavaReader
  include Celluloid
  attr_accessor :s2rgb, :keep_running, :fifo
  
  class BlockingReadline
    include Celluloid
    def initialize(parent)
      @parent = parent
    end
    
    def run
      while true do
        begin
          l = @parent.fifo.readline
          @parent.receive_line l
        rescue Exception => e
          #don't mind it, really
        end
      end
    end
  end
  
  def receive_line(l)
    bars = l.strip.split " "
    bars.map! &:to_i
    if !@active then
      @active = true
      @on_active.call if @on_active
    end
    @framecount += 1
    @flashy.send_rgb @s2rgb.spectral_center_of_mass(bars)
  end
  
  def initialize(path, s2rgb, flashy)
    @s2rgb = s2rgb
    @flashy = flashy
    @keep_running = true
    @fifo_path = path
    open_fifo
    @active = false
    @framecount = 0
    @reader = BlockingReadline.new(self)
  end
  
  def on_active &block
    @on_active = block
  end
  
  def on_idle &block
    @on_idle = block
  end
  
  def spawn_cava
    @cava_pid = spawn("cava")
  end
  
  def idle_timer
    while true do
      Celluloid.sleep 5
      if @framecount == 0 && @active then
        puts "now idle..."
        @active = false
        @on_idle.call if @on_idle
      end
      @framecount = 0
    end
  end
  
  def open_fifo
    begin
      @fifo = File.open(@fifo_path, 'r+')
    rescue Errno::ENOENT => e
      puts "cava fifo: file not found?..."
      #binding.pry
    end
  end
  
  def run
    @reader.async.run
    async.idle_timer
  end  
end

class ControlServer
  attr_accessor :app

  def initialize(opt={})
    @opt = opt || {}
    @opt[:Port] ||= 8053
    
    @s2rgb = opt[:s2rgb]
    @wavegen = opt[:wavegen]
    
    @index = ERB.new(File.read File.join(__dir__, 'web', 'index.erb'))
    @mootools = File.read File.join(__dir__, 'web', 'moo.js')
    if block_given?
      opt[:callback]=Proc.new
    end
    
    def gather_info 
      {active: @s2rgb.get_info, idle: @wavegen.get_info }
    end
    
    def set_maybe(req, obj, param, kind = nil)
      if req.params[param]
        case kind
        when :float
          val = req.params[param].to_f
        when :int
          val = req.params[param].to_i
        else
          val = req.params[param]
        end
        obj.send"#{param}=", val
      end
    end
    
    @app = proc do |env|
      resp = []
      headers = {}
      code = 200
      body = env["rack.input"].read
      chunked = false
      
      req = Rack::Request.new(env)
      
      if req.request_method == "POST"
        set_maybe req, @s2rgb, "peaks_measure_count", :int
        set_maybe req, @s2rgb, "colorscale", :float
        set_maybe req, @s2rgb, "colordrift", :float
        set_maybe req, @s2rgb, "redblue_shift", :float
        
        set_maybe req, @wavegen, "color_cycling_speed", :float
        set_maybe req, @wavegen, "current_color"
        set_maybe req, @wavegen, "brightness_cycling_speed", :float
        set_maybe req, @wavegen, "current_brightness", :float
        
        headers["Content-Type"] = "text/json"
        resp << JSON.generate(gather_info)
      else
        case env["REQUEST_PATH"] || env["PATH_INFO"]
        when "/"
          resp << @index.result(binding)
        when "/info"
          resp << JSON.generate(gather_info)
          headers["Content-Type"]="text/json"
        when "/moo.js"
          resp << @mootools
          headers["Content-Type"]="text/javascript"
        else
          code = 404
          resp << (env["REQUEST_PATH"] || env["PATH_INFO"])
          resp << " not found"
        end
      end

      if @opt[:callback]
        @opt[:callback].call(env)
      end

      headers["Content-Length"]=resp.join("").length.to_s unless chunked

      [ code, headers, resp ]
    end

    @opt = Rack::Handler::Reel::DEFAULT_OPTIONS.merge(@opt)
    @app = Rack::CommonLogger.new(@app, STDOUT) unless @opt[:quiet]
  end

  def run
    ENV['RACK_ENV'] = @opt[:environment].to_s if @opt[:environment]
    @supervisor = Reel::Rack::Server.supervise(as: :reel_rack_server, args: [@app, @opt])
    
    
    #if __FILE__ == $PROGRAM_NAME
    #  begin
    #    sleep
    #  rescue Interrupt
    #    Celluloid.logger.info "Interrupt received... shutting down" unless @opt[:quiet]
    #    @supervisor.terminate
    #  end
    #end
  end
  
  def stop
    @supervisor.terminate
  end
end

class Wavegen
  include Celluloid
  attr_accessor :color_cycling_speed, :brightness_cycling_speed
  def initialize(flashist)
    @flashist = flashist
    @color_cycling_speed = 0.003
    @x = 0
    @min = 0 #2.0/255
    @a = @min
    @brightness_cycling_speed = 0.001
    @current_brightness = @min
  end
  
  def get_info
    {
      color_cycling_speed: @color_cycling_speed,
      current_color: @current_color ? @current_color.html : "#101010",
      brightness_cycling_speed: @brightness_cycling_speed
    }
  end

  def current_color=(val)
    begin
      newcolor = Color::RGB.by_css(val)
    rescue Exception => e
      newcolor = nil
    end
    @current_color = newcolor if newcolor
  end
  
  def wave(x)
    (Math.sin((x)*2*Math::PI - Math::PI/2)+1)/2
  end
  
  def generate
    while @running do
      Celluloid.sleep(1.0/30)
      rgb = @color_cycling_speed > 0 ? Color::RGB.new : @current_color
      if @brightness_cycling_speed > 0
        a = wave(@a)
        @current_brightness = a
      end
      if @color_cycling_speed > 0
        rgb.r = wave(@x) * a + @min
        rgb.g = wave(@x+1.0/3) * a + @min
        rgb.b = wave(@x+2.0/3) * a + @min
      elsif @brightness_cycling_speed > 0
        rgb.r = rgb.r * a
        rgb.g = rgb.g * a
        rgb.b = rgb.b * a
      end
      @current_color = rgb
      @x+=@color_cycling_speed
      @a+=@brightness_cycling_speed
      
      @flashist.send_rgb rgb
    end
  end
  private :generate
  
  def run(rgb = nil)
    @running = true
    self.async.generate
  end
  
  def stop
    @running = false
  end
end

class Control
  include Celluloid
  def initialize
    @flashist = Flashist.new
    @s2rgb = SpectrumToRGB.new
    @wavegen = Wavegen.new @flashist
    @idle = false
    
    @cava = CavaReader.new "/tmp/cava.fifo", @s2rgb, @flashist
    @cava.on_idle do
      @idle = true
      @wavegen.run
    end
    @cava.on_active do
      @wavegen.stop
    end
    @server = ControlServer.new(s2rgb: @s2rgb, wavegen: @wavegen)
  end
  
  def ping_timer
    while true do
      Celluloid.sleep(1)
      if @idle then
        #ping device
        puts "ping"
        @flashist.send_hello
      end
      
    end
  end
  private :ping_timer
  
  def run
    @server.run
    @wavegen.run
    @cava.run
    self.async.ping_timer
  end
end

control = Control.new
control.run

sleep
