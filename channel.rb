require "google/apis/calendar_v3"
require "googleauth"
require "googleauth/stores/file_token_store"
require "date"
require "fileutils"
require "json"

OOB_URI = "urn:ietf:wg:oauth:2.0:oob".freeze
APPLICATION_NAME = "Google Calendar API Ruby Quickstart".freeze
CREDENTIALS_PATH = "credentials.json".freeze
# The file token.yaml stores the user's access and refresh tokens, and is
# created automatically when the authorization flow completes for the first
# time.
TOKEN_PATH = "token.yaml".freeze
SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR
CALLBACK_URL = <CALLBACK URL>

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

def make_channel(calendar_id)
  req = Google::Apis::CalendarV3::Channel.new
  req.id = SecureRandom.uuid
  req.type = 'web_hook'
  req.address = CALLBACK_URL
  result = @service.watch_event(calendar_id,
                               req)
  File.open("channel.json", "w") do |f|
    JSON.dump(result,f)
  end  
end

# id = headers["HTTP_X_GOOG_CHANNEL_ID"]
# resource_id = headers["HTTP_X_GOOG_RESOURCE_ID"]
def stop_channel(id, resource_id)
  channel = Google::Apis::CalendarV3::Channel.new(
    id: id,
    resource_id: resource_id)
  response = @service.stop_channel(channel)
  puts "Success!"
end

# Initialize the API
@service = Google::Apis::CalendarV3::CalendarService.new
@service.client_options.application_name = APPLICATION_NAME
@service.authorization = authorize


if ARGV[0] == "make"
  if File.exist?("channel.json")
    puts "Channel already exsits."
  else
    make_channel(ARGV[1])
  end
elsif ARGV[0] == "stop"
  id , resource_id = nil, nil
  File.open("channel.json") do |f|
    hash = JSON.load(f)
    id = hash["id"]
    resource_id = hash["resourceId"]
  end
  stop_channel(id, resource_id)
  File.delete("channel.json")
end
