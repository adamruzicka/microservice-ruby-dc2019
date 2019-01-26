require 'microservice'
require 'webrick'

rack = Rack::Builder.app do
  run Rack::URLMap.new('/'      => Sinatra.new(Microservice::Api),
                       '/admin' => Sinatra.new(Microservice::AdminApi))
end
Rack::Server.new(:app => rack, :Port => 4567, :Host => '0.0.0.0', :AccessLog => [], Logger: WEBrick::Log.new("/dev/null")).start
