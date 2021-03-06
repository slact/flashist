#!/usr/bin/ruby
require 'rubygems'

begin
  # use `bundle install --standalone' to get this...
  require_relative 'bundle/bundler/setup'
rescue LoadError
  # fall back to regular bundler if the developer hasn't bundled standalone
  require 'bundler'
  require 'bundler/setup'
end

require "optparse"
require 'ruby-conf'

require "celluloid"
require "celluloid/current"
require "celluloid/logger"
require "rawhid"
require "erb"

require "redis"
require "json"

require 'reel/rack'
require "color"

#require "pry"

opt = {
  config_file: "/etc/flashist/control.conf"
}

opt_parser = OptionParser.new do |opts|
  opts.on("-c", "--config PATH (#{opt[:config_file]})", "config file"){|v| opt[:config_file] = v}
end
opt_parser.parse!

load opt[:config_file]
$conf = RubyConf.flashist

class Flashist #don't punch me bro
  include Celluloid
  
  def initialize
    init_device
  end
  
  def init_device
    #puts "init device"
    begin
      @dev = RawHID.new(*$conf.device)
    rescue RawHID::RawHIDError => e
      #puts "flashist device couldn't be opened"
    end
    if @dev
      puts "flashist device connected"
    end
  end
  
  def fade_start(sec)
    @fade_time = sec
    @fade_start = Time.now.to_f
    @fade_from = @last_rgb_frame || Color::RGB.new(0,0,0)
    #puts "fade from #{@fade_from.r}, #{@fade_from.g}, #{@fade_from.b} for #{sec} sec"
  end
  
  def send_raw_bytes(*args)
    init_device unless @dev
    begin
      @dev.write(args, 100) if @dev
    rescue RawHID::RawHIDError => e
      puts "device write failed! exception #{e} #{e.class} code #{e.code}"
      @dev.close if @dev
      puts "closed"
      @dev=nil
      puts "#{@dev.to_s}"
      sleep 0.1 
      
    end
  end
  
  private :send_raw_bytes
  
  def send_raw(*args)
    self.async.send_raw_bytes(*args)
  end
  def send_rgb(rgb)
    if @fade_start
      t = (Time.now.to_f - @fade_start).to_f/@fade_time
      if t > 1
        @fade_start = nil
        t = 1.0
      end
      t=(1-t)
      dr = (@fade_from.r - rgb.r)*t
      dg = (@fade_from.g - rgb.g)*t
      db = (@fade_from.b - rgb.b)*t 
      r=(rgb.r + dr)*255
      g=(rgb.g + dg)*255
      b=(rgb.b + db)*255
      #puts "fading, t=#{t}, [#{dr}]#{r.to_i},[#{dg}]#{g.to_i} [#{db}]#{b.to_i}"
    else
      r = rgb.r*255.to_i
      g = rgb.g*255.to_i
      b = rgb.b*255.to_i
    end
    @last_rgb_frame = rgb
    self.async.send_raw(42, r.to_i, g.to_i, b.to_i)
  end
  def send_hello
    send_raw ">"
  end
end

class SpectrumToRGB
  attr_accessor :colordrift, :colorscale, :peaks_measure_count, :redblue_shift, :amplification
  
  def initialize
    @offset = 0
    
    @peaks_measure_count = 6
    @colordrift = 0.008
    @colorscale = 1.5
    @redblue_shift = 0
    @floor = 0
    @amplification = 4
  end
  
  def idle_max_level
    @floor + 2
  end
  
  def get_info
    {
      peaks_measure_count: @peaks_measure_count,
      amplification: @amplification,
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
    l = l * @amplification
    l = 0.999 if l >= 0.999 # dunno why, but l=1.0 translates to black RGB
    
    #puts [h.to_i, s, l.round(5)].to_s
    
    hsl = Color::HSL.new(h,s*100.0,l*100.0)
    rgb = hsl.to_rgb
    
    if rgb.frozen? && @redblue_shift
      rgb = Color::RGB.new(rgb.r, rgb.g, rgb.b)
    end
    
    if @floor > 0
      range = 255 - @floor
      incr = @floor.to_f/255
      rgb.r = rgb.r * range + incr
      rgb.g = rgb.g * range + incr
      rgb.b = rgb.b * range + incr
    end
    
    if @redblue_shift > 0
      swap = rgb.b * @redblue_shift.abs
      rgb.b = [rgb.b - swap, 0.0].max
      rgb.r = [rgb.r + swap, 1.0].min
    elsif @redblue_shift < 0
      swap = rgb.r * @redblue_shift.abs
      rgb.r = [rgb.r - swap, 0].max
      rgb.b = [rgb.r + swap, 1].min
    end
    
    #puts [rgb.r.round(4), rgb.g.round(4), rgb.b.round(4)].to_s

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
        fifo = @parent.fifo
        if fifo.nil?
          Celluloid.sleep 1
          @parent.open_fifo
        else
          begin
            l = fifo.readline
            @parent.receive_line l
          rescue Exception => e
            #don't mind it, really
            Celluloid.sleep 0.1
          end
        end
      end
    end
  end
  
  def receive_line(l)
    bars = l.strip.split " "
    bars.map! &:to_i
    rgb = @s2rgb.spectral_center_of_mass(bars)
    maxidle = @s2rgb.idle_max_level.to_f/255
    
    #puts "#{(rgb.r*255).to_i} #{(rgb.g*255).to_i} #{(rgb.b*255).to_i}, max: #{(maxidle *255).to_i}. active: #{@active}"
    
    if rgb.r > maxidle || rgb.g > maxidle || rgb.b > maxidle
      @framecount += 1
      if !@active then
        puts "now active..."
        @active = true
        @on_active.call if @on_active
      end
    end
    @flashy.send_rgb rgb unless !@active
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
      puts "cava fifo: can't open #{@fifo_path}"
      puts "make the file"
      system "mkfifo #{@fifo_path}"
      puts @fifo
    end
  end
  
  def run
    @reader.async.run
    async.idle_timer
  end  
end

class ControlServer
  attr_accessor :app

  def initialize(control)
    @opt = {}
    @opt[:Port] = $conf.server_port || 8080
    
    @control = control
    
    @index = ERB.new(File.read File.join(__dir__, 'web', 'index.erb'))
    @mootools = File.read File.join(__dir__, 'web', 'moo.js')
    @jscolor = File.read File.join(__dir__, 'web', 'jscolor.min.js')
    if block_given?
      opt[:callback]=Proc.new
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
        saved_params = @control.set_runtime_params req.params
        headers["Content-Type"] = "text/json"
        resp << JSON.generate(saved_params)
      else
        headers["Cache-Control"] = "max-age=310"
        case env["REQUEST_PATH"] || env["PATH_INFO"]
        when "/"
          runtime_params = @control.get_runtime_params
          active = runtime_params[:active]
          idle = runtime_params[:idle]
          resp << @index.result(binding)
        when "/info"
          resp << JSON.generate(@control.get_runtime_params)
          headers["Content-Type"]="text/json"
          headers["Cache-Control"] = "private"
        when "/moo.js"
          resp << @mootools
          headers["Content-Type"]="text/javascript"
          headers["Cache-Control"] = "public"
        when "/jscolor.min.js"
          resp << @jscolor
          headers["Content-Type"]="text/javascript"
          headers["Cache-Control"] = "public"
        else
          code = 404
          resp << (env["REQUEST_PATH"] || env["PATH_INFO"])
          resp << " not found"
        end
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
  attr_accessor :color_cycling_speed, :brightness_cycling_speed, :brightness_cycling_min, :brightness_cycling_max
  def initialize(flashist)
    @flashist = flashist
    @color_cycling_speed = 0.003
    @x = 0
    @brightness_cycling_min = 0.0
    @brightness_cycling_max = 1.0
    @a = 0
    @brightness_cycling_speed = 0.001
    @current_brightness = 0
    
  end
  
  def get_info
    {
      color_cycling_speed: @color_cycling_speed,
      static_color: @static_color ? @static_color.html : false,
      brightness_cycling_speed: @brightness_cycling_speed,
      brightness_cycling_min: @brightness_cycling_min,
      brightness_cycling_max: @brightness_cycling_max
    }
  end

  def static_color=(val)
    prev_static_color = @static_color
    begin
      newcolor = Color::RGB.by_css(val)
    rescue Exception => e
      newcolor = nil
    end
    @static_color = newcolor
    if prev_static_color != @static_color
      @flashist.fade_start 1
    end
  end
  
  def wave(x)
    (Math.sin((x)*2*Math::PI - Math::PI/2)+1)/2
  end
  
  def generate
    while @running do
      Celluloid.sleep(1.0/30)
      if @static_color
        rgb = @static_color
      else
        rgb = @color_cycling_speed > 0 ? Color::RGB.new : @current_color
        rgb = Color::RGB.new unless rgb
        if rgb.frozen?
          rgb = Color::RGB.new(rgb.r, rgb.g, rgb.b)
        end
        a = wave(@a)
        @current_brightness = a
        rgb.r = wave(@x) * a
        rgb.g = wave(@x+1.0/3) * a
        rgb.b = wave(@x+2.0/3) * a
        if @brightness_cycling_min > 0 || @brightness_cycling_max < 1
          range = @brightness_cycling_max.to_f - @brightness_cycling_min
          rgb.r = rgb.r * range + @brightness_cycling_min
          rgb.g = rgb.g * range + @brightness_cycling_min
          rgb.b = rgb.b * range + @brightness_cycling_min
        end
        @current_color = rgb
        @x+=@color_cycling_speed
        @a+=@brightness_cycling_speed
      end
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
    @idle = true
    
    @cava = CavaReader.new $conf.cava_fifo, @s2rgb, @flashist
    @cava.on_idle do
      @idle = true
      @flashist.fade_start 4
      @wavegen.run
      true
    end
    @cava.on_active do
      @idle = false
      @flashist.fade_start 2
      @wavegen.stop
      true
    end
    @server = ControlServer.new(self)
    if $conf.redis
      @redis = Redis.new url: $conf.redis
      runtime_json = @redis.get($conf.redis_key || "flashist:runtime") rescue nil
      if runtime_json
        rt = JSON.parse(runtime_json) rescue nil
        if rt then
          set_runtime_params rt['active'] if rt['active']
          set_runtime_params rt['idle'] if rt['idle']
        end
      end
    end
  end
  
  def ping_timer
    while true do
      Celluloid.sleep(2)
      if @idle then
        #ping device
        #puts "ping"
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
    sleep 1
    #drop pidfile
    File.write($conf.pidfile, Process.pid)
  end
  
  def set_maybe(params, obj, param, kind = nil)
    if params[param]
      case kind
      when :float
        val = params[param].to_f
      when :int
        val = params[param].to_i
      else
        val = params[param]
      end
      obj.send"#{param}=", val
    end
  end
  private :set_maybe
  
  def set_runtime_params(params)
    set_maybe params, @s2rgb, "active_on", :int
    set_maybe params, @s2rgb, "peaks_measure_count", :int
    set_maybe params, @s2rgb, "amplification", :int
    set_maybe params, @s2rgb, "colorscale", :float
    set_maybe params, @s2rgb, "colordrift", :float
    set_maybe params, @s2rgb, "redblue_shift", :float
    
    if params["static_color_enabled"]
      set_maybe params, @wavegen, "static_color"
    else
      set_maybe params, @wavegen, "idle_on", :int
      set_maybe params, @wavegen, "color_cycling_speed", :float
      set_maybe params, @wavegen, "brightness_cycling_speed", :float
      set_maybe params, @wavegen, "current_brightness", :float
      set_maybe params, @wavegen, "brightness_cycling_min", :float
      set_maybe params, @wavegen, "brightness_cycling_max", :float
      @wavegen.static_color=false
    end
    save_runtime_params
  end
  
  def save_runtime_params
    params = get_runtime_params
    if @redis
      @redis.set($conf.redis_key || "flashist:runtime",  JSON.generate(params)) rescue nil
    end
    params
  end
  
  def get_runtime_params
    {active: @s2rgb.get_info, idle: @wavegen.get_info, state: @idle ? "idle" : "active" }
  end
  
  
end

control = Control.new
control.run

sleep
