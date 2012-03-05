# Note: These rake tasks are here mainly as examples to follow. You're going to want
# to write your own rake tasks that use the locations of your red5 instances. 

require 'red5wrapper'

namespace :red5wrapper do
  
  red5 = {
    :red5_home => File.expand_path("#{File.dirname(__FILE__)}/../red5"),
    :red5_port => "5080",
#    :java_opts=>["-Xms1024m -Xmx1024m -XX:MaxPermSize=256m"]
  }
  
  desc "Return the status of red5"
  task :status do
    status = Red5wrapper.is_red5_running?(red5) ? "Running: #{Red5wrapper.pid(red5)}" : "Not running"
    puts status
  end
  
  desc "Start red5"
  task :start do
    Red5wrapper.start(red5)
    puts "red5 started at PID #{Red5wrapper.pid(red5)}"
  end
  
  desc "stop red5"
  task :stop do
    Red5wrapper.stop(red5)
    puts "red5 stopped"
  end
  
  desc "Restarts red5"
  task :restart do
    Red5wrapper.stop(red5)
    Red5wrapper.start(red5)
  end

  desc "Init Hydrant configuration" 
  task :init => [:environment] do
    if !ENV["environment"].nil? 
      RAILS_ENV = ENV["environment"]
    end
    
    RED5_HOME = File.expand_path(File.dirname(__FILE__) + '/../../red5')
    
    RED5_PARAMS = {
      :quiet => ENV['HYDRA_CONSOLE'] ? false : true,
      :red5_home => RED5_HOME_TEST,
      :red5_port => 5080,
    }
  end

  desc "Copies the default Matterhorn config for the bundled red5"
  task :config_matterhorn => [:init] do
    FileList['matterhorn/conf/*'].each do |f|  
      cp("#{f}", RED5_PARAMS[:red5_home] + '/conf/', :verbose => true)
    end
  end
  
  desc "Copies the default Matterhorn configs into the bundled red5"
  task :config do
    Rake::Task["red5:config_matterhorn"].invoke
  end
end
