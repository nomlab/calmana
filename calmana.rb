require 'sinatra'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'google/apis/calendar_v3'
require 'date'
require 'fileutils'
require 'json'
require 'net/http'
require 'pstore'

set :port, 40024
set :bind, '0.0.0.0'


class Channel
  def new()
  end

  def make_channel
    begin
      req = Google::Apis::CalendarV3::Channel.new
      req.id = SecureRandom.uuid
      req.type = 'web_hook'
      req.address = CALLBACK_URL
      result = service.watch_event(CALENDAR_ID,
                                   req)
    end
    
  end

  def get_event
    result = service.list_events(CALENDAR_ID)
    set = YAML.load_file('settings.yaml')
    calendars = set["calendar_list"]
    calendars.each do |calendar|
      name = calendar["name"]
      calendar_id = calendar["calendar_id"]
      next_sync_token = calendar["next_sync_token"]
      page_token = nil
      if next_sync_token.nul?
        response = service.list_events(calendar_id)
        while response.next_sync_token.nil?
          response = service.list_events(calendar_id,
                                         page_token: response.next_page_token)
        end
        calendar["next_sync_token"] = response.next_sync_token
      else
        response = service.list_events(calendar_id,
                                       sync_token: next_sync_token)
        calendar["next_sync_token"] = response.next_sync_token
        if !response.items.empty?
          puts response.summary
          response.items.each do |e|
            open(File.dirname(__FILE__) + "/db/" + name + ".json", "a") do |f|
              f.write(JSON.pretty_generate(e.to_h))
              f.write(",\n")
              f.close
            end
          end
        end
      end
    end
  end
end

OOB_URI = "urn:ietf:wg:oauth:2.0:oob".freeze
APPLICATION_NAME = "Calmana".freeze
CREDENTIALS_PATH = "credentials.json".freeze
# The file token.yaml stores the user's access and refresh tokens, and is
# created automatically when the authorization flow completes for the first
# time.
TOKEN_PATH = "token.yaml".freeze
SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY
CALLBACK_URL = 'https://calmana.swlab.cs.okayama-u.ac.jp'
CALENDAR_ID = 'primary'
    
##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization. If authorization is required,
# the user's default browser will be launched to approve the request.
#
# @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
def authorize
  client_id = Google::Auth::ClientId.from_file CREDENTIALS_PATH
  token_store = Google::Auth::Stores::FileTokenStore.new file: TOKEN_PATH
  authorizer = Google::Auth::UserAuthorizer.new client_id, SCOPE, token_store
  user_id = "default"
  credentials = authorizer.get_credentials user_id
  if credentials.nil?
    url = authorizer.get_authorization_url base_url: OOB_URI
    puts "Open the following URL in the browser and enter the " \
         "resulting code after authorization:\n" + url
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI
    )
  end
  credentials
end

before do
  # Initialize the API
  @service = Google::Apis::CalendarV3::CalendarService.new
  @service.client_options.application_name = APPLICATION_NAME
  @service.authorization = authorize
end

get '/' do
  "Hello"
end

get '/watch' do
  'watch'
end

get "/.well-known/acme-challenge/:name"do |n|
  Net::HTTP.start("www.swlab.cs.okayama-u.ac.jp") do |http|
    res = http.get("/.well-known/acme-challenge/#{n}")
    open(".well-known/acme-challenge/#{n}", "wb"){|f|
      f.write(res)
      f.write(res.body)
    }
    res.body
  end
end

post '/watch' do
  set = YAML.load_file('settings.yaml')

  File.open("test.log", "a") do |f|
    headers = request.env.select { |k, v| k.start_with?("HTTP_") }
    f.write(headers["HTTP_X_GOOG_RESOURCE_STATE"] == "exists")
    if headers["HTTP_X_GOOG_RESOURCE_STATE"] == "exists" 
      headers.each do |k, v|
        f.write("#{k}->#{v}\n")
        # response = service.list_events(calendar_id,
        #                                sync_token: )
      end
    elsif headers["HTTP_X_GOOG_RESOURCE_STATE"] == "sync"
      calendar_id = headers["HTTP_X_GOOG_RESOURCE_ID"]
      calendar = set[calendar_id]
      response = @service.list_events(calendar_id)
      while response.next_sync_token.nil?
        response = @service.list_events(calendar_id,
                                       page_token: response.next_page_token)
      end
      calendar["next_sync_token"] = response.next_sync_token
      calendar["expiration"] = headers["HTTP_X_GOOG_EXPIRATION"]
    end
    
    f.write("#{headers.class}\n")
  end
end
