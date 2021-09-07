# coding: utf-8
require 'bundler/setup'
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

post '/watch' do
  hash = Hash.new{ |h, k| h[k] = {} }
  headers = request.env.select { |k, v| k.start_with?("HTTP_") }

  ## 予定の変更が行われたときの処理
  if headers["HTTP_X_GOOG_RESOURCE_STATE"] == "exists"
    # next_sync_token, expiration が保存された config.json を読み込み
    File.open("config.json") do |f|
      hash = JSON.load(f)
    end

    puts hash

    # カレンダID を取得
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])

    # 変更された予定を取得
    response = @service.list_events(calendar_id,
                                    sync_token: hash["next_sync_token"])

    # 変更内容を保存
    file_name = DateTime.now.strftime("%Y%m%d%H%M%S")
    File.open("result/#{file_name}.json","a") do |f|
      JSON.dump(response, f)
    end

    # config.json の next_sync_token を書き換え
    hash["next_sync_token"] = response.next_sync_token
    puts hash
    File.open("config.json", "w") do |f|
      JSON.dump(hash, f)
    end

  ## チャンネルが作成されたときの処理 
  elsif headers["HTTP_X_GOOG_RESOURCE_STATE"] == "sync"
    # カレンダID を取得
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])

    # Google Calendar API の Events:list を繰り返し実行することで
    # next_page_token を取得
    response = @service.list_events(calendar_id)
    while response.next_sync_token.nil?
      response = @service.list_events(calendar_id,
                                      page_token: response.next_page_token)
    end

    # next_page_token，expiration を config.json に保存
    # (現時点では expiration をうまく活用できていない)
    hash["next_sync_token"] = response.next_sync_token
    hash["expiration"] = headers["HTTP_X_GOOG_CHANNEL_EXPIRATION"]
    File.open("config.json", "w") do |f|
      JSON.dump(hash, f)
    end
  end  
end
