# Red5wrapper is a Singleton class, so you can only create one red5 instance at a time.
require 'loggable'
require 'singleton'
require 'fileutils'
require 'shellwords'
require 'socket'
require 'timeout'
require 'childprocess'
require 'active_support/core_ext/hash'
require 'net/http'

#Dir[File.expand_path(File.join(File.dirname(__FILE__),"tasks/*.rake"))].each { |ext| load ext } if defined?(Rake)

class Red5wrapper
  
  include Singleton
  include Loggable
  
  attr_accessor :port         # What port should red5 start on? Default is 5080
  attr_accessor :red5_home   # Where is red5 located? 
  attr_accessor :startup_wait # After red5 starts, how long to wait until starting the tests? 
  attr_accessor :quiet        # Keep quiet about red5 output?
  attr_accessor :base_path    # The root of the application. Used for determining where log files and PID files should go.
  attr_accessor :java_opts    # Options to pass to java (ex. ["-Xmx512mb", "-Xms128mb"])
  attr_accessor :port         # The port red5 should listen on
  
  # configure the singleton with some defaults
  def initialize(params = {})
    if defined?(Rails.root)
      @base_path = Rails.root
    else
      @base_path = "."
    end

    logger.debug 'Initializing red5wrapper'
  end
  
  # Methods inside of the class << self block can be called directly on Red5wrapper, as class methods. 
  # Methods outside the class << self block must be called on Red5wrapper.instance, as instance methods.
  class << self
    
    def load_config
      if defined? Rails 
        config_name =  Rails.env 
        app_root = Rails.root
      else 
        config_name =  ENV['environment']
        app_root = ENV['APP_ROOT']
        app_root ||= '.'
      end
      filename = "#{app_root}/config/red5.yml"
      begin
        file = YAML.load_file(filename)
      rescue Exception => e
        logger.warn "Didn't find expected red5wrapper config file at #{filename}, using default file instead."
        file ||= YAML.load_file(File.join(File.dirname(__FILE__),"../config/red5.yml"))
        #raise "Unable to load: #{file}" unless file
      end
      config = file.with_indifferent_access
      config[config_name] || config[:default]
    end
    

    # Set the red5 parameters. It accepts a Hash of symbols. 
    # @param [Hash<Symbol>] params
    # @param [Symbol] :red5_home Required. Where is red5 located? 
    # @param [Symbol] :red5_port What port should red5 start on? Default is 5080
    # @param [Symbol] :startup_wait After red5 starts, how long to wait before running tests? If you don't let red5 start all the way before running the tests, they'll fail because they can't reach red5.
    # @param [Symbol] :quiet Keep quiet about red5 output? Default is true. 
    # @param [Symbol] :java_opts A list of options to pass to the jvm 
    def configure(params = {})
      red5_server = self.instance
      red5_server.reset_process!
      red5_server.quiet = params[:quiet].nil? ? true : params[:quiet]
      if defined?(Rails.root)
       base_path = Rails.root
      elsif defined?(APP_ROOT)
       base_path = APP_ROOT
      else
       raise "You must set either Rails.root, APP_ROOT or pass :red5_home as a parameter so I know where red5 is" unless params[:red5_home]
      end
      red5_server.red5_home = params[:red5_home] || File.expand_path(File.join(base_path, 'red5'))
      ENV['RED5_HOME'] = red5_server.red5_home
      red5_server.port = params[:red5_port] || 5080
      red5_server.startup_wait = params[:startup_wait] || 5
      red5_server.java_opts = params[:java_opts] || []
      return red5_server
    end
   
     
    # Wrap the tests. Startup red5, yield to the test task, capture any errors, shutdown
    # red5, and return the error. 
    # @example Using this method in a rake task
    #   require 'red5wrapper'
    #   desc "Spin up red5 and run tests against it"
    #   task :newtest do
    #     red5_params = { 
    #       :red5_home => "/path/to/red5", 
    #       :quiet => false, 
    #       :red5_port => 8983, 
    #       :startup_wait => 30
    #     }
    #     error = Red5wrapper.wrap(red5_params) do   
    #       Rake::Task["rake:spec"].invoke 
    #       Rake::Task["rake:cucumber"].invoke 
    #     end 
    #     raise "test failures: #{error}" if error
    #   end
    def wrap(params)
      error = false
      red5_server = self.configure(params)

      begin
        red5_server.start
        yield
      rescue
        error = $!
        puts "*** Error starting red5: #{error}"
      ensure
        # puts "stopping red5 server"
        red5_server.stop
      end

      return error
    end
    
    # Convenience method for configuring and starting red5 with one command
    # @param [Hash] params: The configuration to use for starting red5
    # @example 
    #    Red5wrapper.start(:red5_home => '/path/to/red5', :red5_port => '8983')
    def start(params)
       Red5wrapper.configure(params)
       Red5wrapper.instance.start
       return Red5wrapper.instance
    end
    
    # Convenience method for configuring and starting red5 with one command. Note
    # that for stopping, only the :red5_home value is required (including other values won't 
    # hurt anything, though). 
    # @param [Hash] params: The red5_home to use for stopping red5
    # @return [Red5wrapper.instance]
    # @example 
    #    Red5wrapper.stop_with_params(:red5_home => '/path/to/red5')
    def stop(params)
       Red5wrapper.configure(params)
       Red5wrapper.instance.stop
       return Red5wrapper.instance
    end
    
    # Determine whether the red5 at the given red5_home is running
    # @param [Hash] params: :red5_home is required. Which red5 do you want to check the status of?
    # @return [Boolean]
    # @example
    #    Red5wrapper.is_red5_running?(:red5_home => '/path/to/red5')
    def is_red5_running?(params)      
      Red5wrapper.configure(params)
      pid = Red5wrapper.instance.pid
      return false unless pid
      true
    end
    
    # Return the pid of the specified red5, or return nil if it isn't running
    # @param [Hash] params: :red5_home is required.
    # @return [Fixnum] or [nil]
    # @example
    #    Red5wrapper.pid(:red5_home => '/path/to/red5')
    def pid(params)
      Red5wrapper.configure(params)
      pid = Red5wrapper.instance.pid
      return nil unless pid
      pid
    end
    
    # Check to see if the port is open so we can raise an error if we have a conflict
    # @param [Fixnum] port the port to check
    # @return [Boolean]
    # @example
    #  Red5wrapper.is_port_open?(8983)
    def is_port_in_use?(port)
      begin
        Timeout::timeout(1) do
          begin
            s = TCPSocket.new('127.0.0.1', port)
            s.close
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          rescue
            return false
          end
        end
      rescue Timeout::Error
      end

      return false
    end
    
    # Check to see if the pid is actually running. This only works on unix. 
    def is_pid_running?(pid)
      begin
        return Process.getpgid(pid) != -1
      rescue Errno::ESRCH
        return false
      end
    end
    
    def is_responding?(port)
      begin
        Timeout::timeout(1) do
          begin
            response = Net::HTTP.get_response(URI.parse("http://localhost:#{port}/login.html"))
            return true if "200" == response.code
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          rescue
            return false
          end
        end
      rescue Timeout::Error
      end

      return false
    end
          

    end #end of class << self
    
        
   # What command is being run to invoke red5? 
   def red5_command
     ["./red5.sh"].flatten
   end

#   def java_variables
#     ["-Dred5.port=#{@port}"]
#   end

   # Start the red5 server. Check the pid file to see if it is running already, 
   # and stop it if so. After you start red5, write the PID to a file. 
   # This is the instance start method. It must be called on Red5wrapper.instance
   # You're probably better off using Red5wrapper.start(:red5_home => "/path/to/red5")
   # @example
   #    Red5wrapper.configure(params)
   #    Red5wrapper.instance.start
   #    return Red5wrapper.instance
   def start
     logger.debug "Starting red5 with these values: "
     logger.debug "red5_home: #{@red5_home}"
     logger.debug "red5_command: #{red5_command.join(' ')}"
     
     # Check to see if we can start.
     # 1. If there is a pid, check to see if it is really running
     # 2. Check to see if anything is blocking the port we want to use     
     if pid
       if Red5wrapper.is_pid_running?(pid)
         raise("Server is already running with PID #{pid}")
       else
         logger.warn "Removing stale PID file at #{pid_path}"
         File.delete(pid_path)
       end
       if Red5wrapper.is_port_in_use?(self.port)
         raise("Port #{self.port} is already in use.")
       end
     end
     Dir.chdir(@red5_home) do
       process.start
     end
     FileUtils.makedirs(pid_dir) unless File.directory?(pid_dir)
     begin
       f = File.new(pid_path,  "w")
     rescue Errno::ENOENT, Errno::EACCES
       f = File.new(File.join(@base_path,'tmp',pid_file),"w")
     end
     f.puts "#{process.pid}"
     f.close
     logger.debug "Wrote pid file to #{pid_path} with value #{process.pid}"
     startup_wait!
   end

   # Wait for the red5 server to start and begin listening for requests
   def startup_wait!
     begin
     Timeout::timeout(startup_wait) do
       sleep 1 until (Red5wrapper.is_port_in_use? self.port and Red5wrapper.is_responding? self.port)
     end 
     rescue Timeout::Error
       logger.warn "Waited #{startup_wait} seconds for red5 to start, but it is not yet listening on port #{self.port}. Continuing anyway."
     end
   end
 
   def process
     @process ||= begin
        process = ChildProcess.build(*red5_command)
        if self.quiet
          process.io.stderr = File.open(File.expand_path("red5wrapper.log"), "w+")
          process.io.stdout = process.io.stderr
           logger.warn "Logging red5wrapper stdout to #{File.expand_path(process.io.stderr.path)}"
        else
          process.io.inherit!
        end
        process.detach = true

        process
      end
   end

   def reset_process!
     @process = nil
   end

   def stop_process
     @stop_process ||= begin
        stop_process = ChildProcess.build(*red5_stop_command)
        if self.quiet
          stop_process.io.stderr = File.open(File.expand_path("red5wrapper.log"), "w+")
          stop_process.io.stdout = process.io.stderr
          # logger.warn "Logging red5wrapper stdout to #{File.expand_path(process.io.stderr.path)}"
        else
          stop_process.io.inherit!
        end
        stop_process.detach = true

        stop_process
      end
   end

   # Instance stop method. Must be called on Red5wrapper.instance
   # You're probably better off using Red5wrapper.stop(:red5_home => "/path/to/red5")
   # @example
   #    Red5wrapper.configure(params)
   #    Red5wrapper.instance.stop
   #    return Red5wrapper.instance
   def stop    
     logger.debug "Instance stop method called for pid '#{pid}'"
     if pid
       if @process
         @process.stop
       else
         Process.kill("KILL", pid) rescue nil
       end

       begin
         File.delete(pid_path)
       rescue
       end
     end
   end
 

   # The fully qualified path to the pid_file
   def pid_path
     #need to memoize this, becasuse the base path could be relative and the cwd can change in the yield block of wrap
     @path ||= File.join(pid_dir, pid_file)
   end

   # The file where the process ID will be written
   def pid_file
     red5_home_to_pid_file(@red5_home)
   end
   
    # Take the @red5_home value and transform it into a legal filename
    # @return [String] the name of the pid_file
    # @example
    #    /usr/local/red51 => _usr_local_red51.pid
    def red5_home_to_pid_file(red5_home)
      begin
        red5_home.gsub(/\//,'_') << ".pid"
      rescue
        raise "Couldn't make a pid file for red5_home value #{red5_home}"
        raise $!
      end
    end

   # The directory where the pid_file will be written
   def pid_dir
     File.expand_path(File.join(@base_path,'tmp','pids'))
   end
   
   # Check to see if there is a pid file already
   # @return true if the file exists, otherwise false
   def pid_file?
      return true if File.exist?(pid_path)
      false
   end

   # the process id of the currently running red5 instance
   def pid
      File.open( pid_path ) { |f| return f.gets.to_i } if File.exist?(pid_path)
   end
   
end

load File.join(File.dirname(__FILE__),"tasks/red5wrapper.rake") if defined?(Rake)
