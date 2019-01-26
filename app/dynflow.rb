require_relative './example_helper.rb'
require 'rest-client'

module Actions
  module REST
    def post_rest(url, parse_json: true, data: '')
      response = log(url) do
        RestClient::Resource.new(url).post(data)
      end
      parse_json ? MultiJson.load(response.body) : response.body
    end

    def log(url)
      action_logger.info "START POST #{url}"
      response = yield
      action_logger.info " DONE POST #{url} #{response.code}"
      response
    end
  end

  module RevertBooking
    def revert_run
      id = original_output[:response][:id]
      post_rest(original_input[:url] + "/#{id}/compensate")
    end
  end

  class BookHotel < ::Dynflow::Action
    include ::Dynflow::Action::Revertible
    include REST

    def plan(url:, should_fail: false)
      plan_self :url => url, :should_fail => should_fail
    end

    def run
      target_url = input[:url] + (input[:should_fail] ? '/fail' : '/')
      output[:response] = post_rest(target_url)
      if output[:response]['state'] == 'rejected'
        error! "Failed booking at #{input[:url]}"
      else
        action_logger.info "Booking succeeded for #{input[:url]}"
      end
    end
  end

  class BookFlight < ::Dynflow::Action
    include ::Dynflow::Action::Revertible
    include REST
    include RevertBooking

    def run
      output[:response] = post_rest(input[:url])
    end
  end

  class BookTrip < ::Dynflow::Action
    include ::Dynflow::Action::Revertible

    def plan(should_fail)
      sequence do
        plan_action BookFlight,
          :url => 'http://lraservice:8080/dynflow'
        plan_action BookHotel,
          :url => 'http://ruby-api:4567', :should_fail => should_fail
      end
    end
  end
end

Thread.new do
  sleep 1
  ExampleHelper.world.trigger ::Actions::BookTrip, false
end
ExampleHelper.run_web_console
