require 'spec_helper'
require 'rubygems'

  describe Red5wrapper do
    
    # RED51 = 
    
    before(:all) do
      @red5_params = {
        :quiet => false,
        :red5_home => "/path/to/red5",
        :red5_port => 5080,
        :startup_wait => 0,
#        :java_opts => ["-Xms1024m", "-Xmx1024m", "-XX:MaxPermSize=256m"]
      }
    end

    context "config" do
      it "loads the application red5.yml first" do
        YAML.expects(:load_file).with('./config/red5.yml').once.returns({})
        config = Red5wrapper.load_config
      end

      it "falls back on the distributed red5.yml" do
        fallback_seq = sequence('fallback sequence')
        YAML.expects(:load_file).in_sequence(fallback_seq).with('./config/red5.yml').raises(Exception)
        YAML.expects(:load_file).in_sequence(fallback_seq).with { |value| value =~ /red5.yml/ }.returns({})
        config = Red5wrapper.load_config
      end

      it "supports per-environment configuration" do
        ENV['environment'] = 'test'
        YAML.expects(:load_file).with('./config/red5.yml').once.returns({:test => {:a => 2 }, :default => { :a => 1 }})
        config = Red5wrapper.load_config
        config[:a].should == 2
      end

      it "falls back on a 'default' environment configuration" do
        ENV['environment'] = 'test'
        YAML.expects(:load_file).with('./config/red5.yml').once.returns({:default => { :a => 1 }})
        config = Red5wrapper.load_config
        config[:a].should == 1
      end
    end
    
    context "instantiation" do
      it "can be instantiated" do
        ts = Red5wrapper.instance
        ts.class.should eql(Red5wrapper)
      end

      it "can be configured with a params hash" do
        ts = Red5wrapper.configure(@red5_params) 
        ts.quiet.should == false
        ts.red5_home.should == "/path/to/red5"
        ts.port.should == 5080
        ts.startup_wait.should == 0
      end

      # passing in a hash is no longer optional
      it "raises an error when called without a :red5_home value" do
          lambda { ts = Red5wrapper.configure }.should raise_exception
      end

      it "should override nil params with defaults" do
        red5_params = {
          :quiet => nil,
          :red5_home => '/path/to/red5',
          :red5_port => nil,
          :startup_wait => nil
        }

        ts = Red5wrapper.configure(red5_params) 
        ts.quiet.should == true
        ts.red5_home.should == "/path/to/red5"
        ts.port.should == 5080
        ts.startup_wait.should == 5
      end
      
      it "passes all the expected values to red5 during startup" do
        ts = Red5wrapper.configure(@red5_params) 
        command = ts.red5_command
#        command.should include("-Dred5.port=#{@red5_params[:red5_port]}")
#        command.should include("-Xmx1024m")
	command.should include("red5.sh")
      end

      it "has a pid if it has been started" do
        red5_params = {
          :red5_home => '/tmp'
        }
        ts = Red5wrapper.configure(red5_params) 
        Red5wrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>5454))
        ts.stop
        ts.start
        ts.pid.should eql(5454)
        ts.stop
      end
      
      it "can pass params to a start method" do
        red5_params = {
          :red5_home => '/tmp', :red5_port => 8777
        }
        ts = Red5wrapper.configure(red5_params) 
        ts.stop
        Red5wrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>2323))
        swp = Red5wrapper.start(red5_params)
        swp.pid.should eql(2323)
        swp.pid_file.should eql("_tmp.pid")
        swp.stop
      end
      
      it "checks to see if its pid files are stale" do
        @pending
      end
      
      # return true if it's running, otherwise return false
      it "can get the status for a given red5 instance" do
        # Don't actually start red5, just fake it
        Red5wrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>12345))
        
        red5_params = {
          :red5_home => File.expand_path("#{File.dirname(__FILE__)}/../../red5")
        }
        Red5wrapper.stop(red5_params)
        Red5wrapper.is_red5_running?(red5_params).should eql(false)
        Red5wrapper.start(red5_params)
        Red5wrapper.is_red5_running?(red5_params).should eql(true)
        Red5wrapper.stop(red5_params)
      end
      
      it "can get the pid for a given red5 instance" do
        # Don't actually start red5, just fake it
        Red5wrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>54321))
        red5_params = {
          :red5_home => File.expand_path("#{File.dirname(__FILE__)}/../../red5")
        }
        Red5wrapper.stop(red5_params)
        Red5wrapper.pid(red5_params).should eql(nil)
        Red5wrapper.start(red5_params)
        Red5wrapper.pid(red5_params).should eql(54321)
        Red5wrapper.stop(red5_params)
      end
      
      it "can pass params to a stop method" do
        red5_params = {
          :red5_home => '/tmp', :red5_port => 8777
        }
        Red5wrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>2323))
        swp = Red5wrapper.start(red5_params)
        (File.file? swp.pid_path).should eql(true)
        
        swp = Red5wrapper.stop(red5_params)
        (File.file? swp.pid_path).should eql(false)
      end
      
      it "knows what its pid file should be called" do
        ts = Red5wrapper.configure(@red5_params) 
        ts.pid_file.should eql("_path_to_red5.pid")
      end
      
      it "knows where its pid file should be written" do
        ts = Red5wrapper.configure(@red5_params) 
        ts.pid_dir.should eql(File.expand_path("#{ts.base_path}/tmp/pids"))
      end
      
      it "writes a pid to a file when it is started" do
        red5_params = {
          :red5_home => '/tmp'
        }
        ts = Red5wrapper.configure(red5_params) 
        Red5wrapper.any_instance.stubs(:process).returns(stub('proc', :start => nil, :pid=>2222))
        ts.stop
        ts.pid_file?.should eql(false)
        ts.start
        ts.pid.should eql(2222)
        ts.pid_file?.should eql(true)
        pid_from_file = File.open( ts.pid_path ) { |f| f.gets.to_i }
        pid_from_file.should eql(2222)
      end
      
    end # end of instantiation context
    
    context "logging" do
      it "has a logger" do
        ts = Red5wrapper.configure(@red5_params) 
        ts.logger.should be_kind_of(Logger)
      end
      
    end # end of logging context 
    
    context "wrapping a task" do
      it "wraps another method" do
        Red5wrapper.any_instance.stubs(:start).returns(true)
        Red5wrapper.any_instance.stubs(:stop).returns(true)
        error = Red5wrapper.wrap(@red5_params) do            
        end
        error.should eql(false)
      end
      
      it "configures itself correctly when invoked via the wrap method" do
        Red5wrapper.any_instance.stubs(:start).returns(true)
        Red5wrapper.any_instance.stubs(:stop).returns(true)
        error = Red5wrapper.wrap(@red5_params) do 
          ts = Red5wrapper.instance 
          ts.quiet.should == @red5_params[:quiet]
          ts.red5_home.should == "/path/to/red5"
          ts.port.should == 5080
          ts.startup_wait.should == 0     
        end
        error.should eql(false)
      end
      
      it "captures any errors produced" do
        Red5wrapper.any_instance.stubs(:start).returns(true)
        Red5wrapper.any_instance.stubs(:stop).returns(true)
        error = Red5wrapper.wrap(@red5_params) do 
          raise "this is an expected error message"
        end
        error.class.should eql(RuntimeError)
        error.message.should eql("this is an expected error message")
      end
      
    end # end of wrapping context

    context "quiet mode", :quiet => true do
      it "inherits the current stderr/stdout in 'loud' mode" do
        ts = Red5wrapper.configure(@red5_params.merge(:quiet => false))
        process = ts.process
        process.io.stderr.should == $stderr
        process.io.stdout.should == $stdout
      end

      it "redirect stderr/stdout to a log file in quiet mode" do
        ts = Red5wrapper.configure(@red5_params.merge(:quiet => true))
        process = ts.process
        process.io.stderr.should_not == $stderr
        process.io.stdout.should_not == $stdout
      end
    end
  end
