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

OOB_URI = "urn:ietf:wg:oauth:2.0:oob".freeze
APPLICATION_NAME = "Calmana".freeze
CREDENTIALS_PATH = "credentials.json".freeze
# The file token.yaml stores the user's access and refresh tokens, and is
# created automatically when the authorization flow completes for the first
# time.
TOKEN_PATH = "token.yaml".freeze
SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR
    
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

def extract_calendar(uri)
  calendar_id = uri.split(File::SEPARATOR)[6]
  return calendar_id
end

def stop_channel(id, resource_id)
  channel = Google::Apis::CalendarV3::Channel.new(
    id: id,
    resource_id: resource_id)
  response = @service.stop_channel(channel)
  printf(response)
end

before do
  # Initialize the API
  @service = Google::Apis::CalendarV3::CalendarService.new
  @service.client_options.application_name = APPLICATION_NAME
  @service.authorization = authorize
  @hash = Hash.new{ |h, k| h[k] = {} }
end

get '/' do
  "Hello"
end

get '/watch' do
  'watch'
end

post '/watch' do
  headers = request.env.select { |k, v| k.start_with?("HTTP_") }
  if headers["HTTP_X_GOOG_RESOURCE_STATE"] == "exists"
    # stop_channel(headers["HTTP_X_GOOG_CHANNEL_ID"], headers["HTTP_X_GOOG_RESOURCE_ID"])
    
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])
    printf("#{@hash}")
    response = @service.list_events(calendar_id: calendar_id,
                                    sync_token: @hash["#{calendar_id}"]["next_sync_token"])
    File.open("result.log","a") do |f|
      response.items.each do |e|
        f.write("#{e.summary}\n")
      end
    end
    hash["#{calendar_id}"]["next_sync_token"] = response.next_page_token

  elsif headers["HTTP_X_GOOG_RESOURCE_STATE"] == "sync"
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])
    response = @service.list_events(calendar_id)
    while response.next_sync_token.nil?
      response = @service.list_events(calendar_id,
                                      page_token: response.next_page_token)
    end
    @hash["#{calendar_id}"]["next_sync_token"] = response.next_sync_token
    @hash["#{calendar_id}"]["expiration"] = headers["HTTP_X_GOOG_CHANNEL_EXPIRATION"]
  end  
end
