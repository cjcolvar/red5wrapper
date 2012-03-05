## These tasks get loaded into the host application when red5wrapper is required
require 'yaml'

namespace :red5 do
  
  desc "Return the status of red5"
  task :status => :environment do
    status = Red5wrapper.is_red5_running?(RED5_CONFIG) ? "Running: #{Red5wrapper.pid(RED5_CONFIG)}" : "Not running"
    puts status
  end
  
  desc "Start red5"
  task :start => :environment do
    Red5wrapper.start(RED5_CONFIG)
    puts "red5 started at PID #{Red5wrapper.pid(RED5_CONFIG)}"
  end
  
  desc "stop red5"
  task :stop => :environment do
    Red5wrapper.stop(RED5_CONFIG)
    puts "red5 stopped"
  end
  
  desc "Restarts red5"
  task :restart => :environment do
    Red5wrapper.stop(RED5_CONFIG)
    Red5wrapper.start(RED5_CONFIG)
  end


  desc "Load the red5 config"
  task :environment do
    unless defined? RED5_CONFIG
      RED5_CONFIG = Red5wrapper.load_config
    end
  end

end

