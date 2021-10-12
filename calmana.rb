# coding: utf-8
require 'bundler/setup'
require 'sinatra'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'google/apis/calendar_v3'
require 'date'
require 'time'
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

def stop_channel(id, resource_id)
  channel = Google::Apis::CalendarV3::Channel.new(
    id: id,
    resource_id: resource_id)
  resopnse = @service.stop_channel(channel)
  puts response
end

def extract_calendar(uri)
  calendar_id = uri.split(File::SEPARATOR)[6]
  return calendar_id
end

def file_store(response)
  file_name = DateTime.now.strftime("%Y%m%d%H%M%S")
  File.open("result/#{file_name}.json","w") do |f|
    JSON.dump(response, f)
  end
end

def log_output(event)
  hash = Hash.new{ |h, k| h[k] = {} }
  history = []

  Dir.glob('result/*.json').each do |filename|
    File.open(filename) do |f|
      hash = JSON.load(f)
      hash["items"].each do |h|
        history.push(h)
      end
    end
  end

  event.items.each do |e|
    File.open("calmana.log", "a") do |f|

      same_events = history.select{ |r| r["id"] == e.id }
      same_events = same_events.sort_by {|h| h["updated"] }
      reference = same_events.last

      # if reference.nil?
      #   puts "No same_events"
      #   break
      # end

      # 操作日時の取得
      time = DateTime.now

      # 操作内容の判定
      if e.status == "cancelled"
        f.puts("#{time}, #{e.id}, delete")
        break
      elsif ((e.updated - e.created) * 24 * 60 * 60).to_i < 1
        f.puts("#{time}, #{e.id}, create")
        break
      elsif e.summary != reference["summary"]
        f.puts("#{time}, #{e.id}, update, summary")
      elsif e.start != reference["start"]
        f.puts("#{time}, #{e.id}, update, start_time")
      else
        f.puts("#{time}, #{e.id}, undefined")
      end
    end
  end
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
    # カレンダID を取得
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])

    puts "Event is changed in #{calendar_id}."
    #id = headers["HTTP_X_GOOG_CHANNEL_ID"]
    #resource_id = headers["HTTP_X_GOOG_RESOURCE_ID"]
    #stop_channel(id, resource_id)

    # next_sync_token, expiration が保存された config.json を読み込み
    File.open("config.json") do |f|
      hash = JSON.load(f)
    end

    # カレンダID を取得
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])

    # 変更された予定を取得
    response = @service.list_events(calendar_id,
                                    sync_token: hash["next_sync_token"])

    # 変更内容をログに出力
    log_output(response)

    # 変更された予定をファイル保存
    file_store(response)

    # config.json の next_sync_token を書き換え
    hash["next_sync_token"] = response.next_sync_token
    File.open("config.json", "w") do |f|
      JSON.dump(hash, f)
    end

  ## チャンネルが作成されたときの処理 
  elsif headers["HTTP_X_GOOG_RESOURCE_STATE"] == "sync"
    # カレンダID を取得
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])

    puts "Channel is made in #{calendar_id}"

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
