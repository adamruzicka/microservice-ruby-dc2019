require 'sinatra/base'
require 'rest-client'
require 'logger'

class Log
  include Singleton

  def logger
    @logger ||= WEBrick::Log.new(STDERR)
  end
end

module Microservice
  class Logging
    def initialize(app)
      @app = app
    end

    def call(env)
      ::Log.instance.logger.info "> #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
      result = @app.call(env)
      ::Log.instance.logger.info "< #{env['REQUEST_METHOD']} #{env['PATH_INFO']} #{result.first}"
      result
    end
  end

  class Api < Sinatra::Base
    use Logging

    helpers do
      def repo
        Repo.instance
      end

      def lra_header
        request.env['HTTP_LONG_RUNNING_ACTION']
      end

      def enlist_lra
        return unless lra_header
        base_url = 'http://' + request.env['HTTP_HOST']
        body = %Q(<#{base_url}/complete>; rel="complete"; title="complete URI"; type="text/plain",<#{base_url}/compensate>; rel="compensate"; title="compensate URI"; type="text/plain")
        ::Log.instance.logger.info "Enlisting to #{lra_header}"
        lra_resource.put '', { 'Link': body }
      rescue => e
	      ::Log.instance.logger.error "Failed to enlist to saga: #{e.message}"
      end

      def complete_lra
        lra_resource('close').put '' if lra_header
      end

      def cancel_lra
        lra_resource('cancel').put '' if lra_header
      end

      def lra_resource(path = '')
        RestClient::Resource.new(lra_header)[path]
      end
    end

    post '/async/?' do
      repo.insert(Record.new).to_json
    end

    post '/' do
      enlist_lra
      record = Record.new :state => 'approved', :data => {:lra_header => lra_header }
      record = repo.insert(record).to_json
      ::Log.instance.logger.info "Booking '#{record}' was created"
      # complete_lra
      record
    end

    post '/fail/?' do
      enlist_lra
      record = Record.new :state => 'rejected', :data => {:lra_header => lra_header }
      record = repo.insert(record).to_json
      ::Log.instance.logger.info "Booking '#{record}' could not be created"
      # cancel_lra
      record
    end

    put '/compensate' do
      ::Log.instance.logger.info "LRA ID #{lra_header} compensate call called"
      repo.find_lra(lra_header).each do |record|
        ::Log.instance.logger.info "Revoking booking #{record.id}"
        record.state = 'revoked'       
        Repo.update(record)
      end
    end

    put '/complete' do
      ::Log.instance.logger.info "LRA ID #{lra_header} complete call called"
      repo.find_lra(lra_header).each do |record|
        # Do something
        ::Log.instance.logger.info "Confirming booking #{record.id}"
      end
      ''
    end

    get '/status' do; end

    get '/:id/status' do
      repo.find(params['id']).to_json
    end

    post '/:id/complete' do

    end

    post '/:id/compensate' do
      record = repo.find(params['id'])
      ::Log.instance.logger.info "Revoking booking #{record.id}"
      record.state = 'revoked'
      repo.update(record).to_json
    end
  end
end
