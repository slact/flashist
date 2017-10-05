#!/usr/bin/ruby
require "celluloid"
require 'rubygems'
require 'bundler/setup'
require "timers"
require "hidapi"

require "celluloid/current"
require 'reel/rack'
require "color"
require "color-rgb"

require "pry"
require "awesome_print"

timers = Timers::Group.new
class HIDAPI::Device
  def kill_read_thread
    @thread.kill
    self.shutdown_thread = true
  end
end

#dev = HIDAPI::open(0x16c0, 0x0486)

#dev.kill_read_thread

class Flashist #don't punch me bro
  def initialize
    @dev = HIDAPI::open(0x16c0, 0x0486)
    @dev.kill_read_thread
  end
  
  def send_rgb(rgb)
    #puts [rgb.r, rgb.g, rgb.b].to_s
    @dev.write(42, (rgb.r*255).to_i, (rgb.g*255).to_i, (rgb.b*255).to_i)
  end
  def send_hello
    @dev.write(">")
  end
end

class SpectrumToRGB
  attr_accessor :colordrift, :colorscale, :peaks_measure_count, :redblue_shift
  
  def initialize(r_range=0.33..0.66, g_range=0.66..1, b_range=0..0.33)
    @r=r_range
    @g=g_range
    @b=b_range

    @offset = 0
    
    @peaks_measure_count = 10
    @colordrift = 0
    @colorscale = 1.5
    @redblue_shift = 0
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
    
    s = 1
    l = max_sum.to_f / (@peaks_measure_count * 4096)
    
    #puts [h.to_i, s, l.round(5)].to_s
    
    hsl = Color::HSL.new(h,s*100,l*100)
    rgb = hsl.to_rgb
    
    if rgb.frozen? && @redblue_shift
      rgb = Color::RGB.new(rgb.r, rgb.g, rgb.b)
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
  
  def chop_spectrum(bars)
    ll = bars.length

    cbars=[]
    
    cbars[0] = bars[ll*@r.begin..ll*@r.end]
    cbars[1] = bars[ll*@g.begin..ll*@g.end]
    cbars[2] = bars[ll*@b.begin..ll*@b.end]

    cbright=[]
    cbars.each_with_index do |cbar, i|
      #csum = cbar.inject 0, :+
      #cmax = cbar.count * 4096
      #cbright[i] = ((csum.to_f/cmax)*255).to_i
      
      cbright[i]=((cbar.max.to_f/4096.0)*255).to_i
    end

    @rgb.set(*cbright)
    @dev.write(@rgb.packet)
  end
end


class CavaReader
  include Celluloid
  attr_accessor :s2rgb
  def initialize(path, s2rgb, flashy)
    @f = File.open(path, 'r')
    @s2rgb = s2rgb
    @flashy = flashy
    @keep_running = true
  end

  def run
    while @keep_running do
      l = @f.readline
      bars = l.strip.split " "
      bars.map! &:to_i

      @flashy.send_rgb @s2rgb.spectral_center_of_mass(bars)
    end
  end
  
  def beep
    puts "beeping"
  end

  
end

flashy = Flashist.new
s2rgb = SpectrumToRGB.new
cava = CavaReader.new "/tmp/cava.fifo", s2rgb, flashy
cava.async.run




class ControlServer
  attr_accessor :app

  def initialize(opt={})
    @opt = opt || {}
    @opt[:Port] ||= 8053
    
    @cava = opt[:cava]
    @s2rgb = opt[:s2rgb]
    
    if block_given?
      opt[:callback]=Proc.new
    end

    @app = proc do |env|
      resp = []
      headers = {}
      code = 200
      body = env["rack.input"].read
      chunked = false
      
      req = Rack::Request.new(env)
      
      if req.request_method == "POST"
        awesome_print req.params
        @s2rgb.peaks_measure_count = req.params["peaks_measure_count"].to_i if req.params["peaks_measure_count"]
        @s2rgb.colorscale = req.params["colorscale"].to_f if req.params["colorscale"]
        @s2rgb.colordrift = req.params["colordrift"].to_f if req.params["colordrift"]
        @s2rgb.redblue_shift = req.params["redblue_shift"].to_f if req.params["redblue_shift"]
        headers["Content-Type"] = "text/json"
        resp << "{}"
      else
      
        case env["REQUEST_PATH"] || env["PATH_INFO"]
        when "/"
          resp << "
            <html>
              <head>
                <script type='text/javascript' src='https://cdnjs.cloudflare.com/ajax/libs/mootools/1.6.0/mootools-core.min.js'></script>
                <script type='text/javascript' src='https://cdnjs.cloudflare.com/ajax/libs/mootools-more/1.6.0/mootools-more-compressed.js'></script>
              </head>
              <body>
                <form method='post' action=''>
                  <label>
                    Amplitude peak smoothing
                    <input name='peaks_measure_count' list='smoothings' type='range' min='1' max='90' value='#{@s2rgb.peaks_measure_count}' />
                    <datalist id='smoothings'>
                      <option value='1' label='spiky' >
                      <option value='90' label='smooth' >
                    </datalist>
                  </label>
                  
                  <label>
                    Color responsiveness
                    <input name='colorscale' type='range' min='1' max='3' value='#{@s2rgb.colorscale}' step='0.1' />
                  </label>
                  
                  <label>
                    Color drift
                    <input name='colordrift' list='colordrifts' type='range' min='0' max='0.01' value='#{@s2rgb.colordrift}' step='0.00001' />
                    <datalist id='colordrifts'>
                      <option value='0' label='none' />
                      <option value='0.001' label='slow' />
                      <option value='0.01' label='fast' />
                      <option value='0.1' label='wacky' />
                    </datalist>
                  </label>
                  
                  <label>
                    Color Temperature
                    <input name='redblue_shift' list='temps' type='range' min='-1' max='1' value='#{@s2rgb.redblue_shift}' step='0.01' />
                    <datalist id='temps'>
                      <option value='-1' label='cool' />
                      <option value='0' label='neutral' />
                      <option value='1' label='warm' />
                    </datalist>
                </form>
                
                <script type='text/javascript'>
                  var form = document.getElement('form');
                  var req = new Form.Request(form, null, {resetForm: false});
                  
                  form.getElements('input').each(function(el) {
                    console.log('added');
                    el.addEvent('change', function() {
                      console.log('hey', el);
                      req.send();
                      
                    });
                  });
                
                </script>
              </body>
            </html>
          "
        when "/update"
          
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

server = ControlServer.new(cava: cava, s2rgb: s2rgb)

server.run
cava.wait
