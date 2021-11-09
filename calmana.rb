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
require 'uri'
require 'systemu'
require 'open3'

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
CONFIG_PATH = "config.json".freeze

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
  calendar_id = URI.decode_www_form_component(calendar_id)
  return calendar_id
end

def file_store(response)
  file_name = DateTime.now.strftime("%Y%m%d%H%M%S")
  File.open("result/#{file_name}.json","w") do |f|
    JSON.dump(response, f)
  end
end

def log_output(event)
  puts "ログを出力します．"
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
      time = DateTime.now
      same_events = history.select{ |r| r["id"] == e.id }
      same_events = same_events.sort_by {|h| h["updated"] }
      reference = same_events.last

      # 操作日時の取得
      if e.start
        if e.start.date_time
          start = e.start.date_time
        else
          start = e.start.date
        end
      end
      if reference.nil?
        summary = e.summary
        ref_start = start
      else
        summary = reference['summary']
        if reference["start"]
          if reference["start"]["date_time"]
            ref_start = reference["start"]["date_time"]
          else
            ref_start = reference["start"]["date"]
          end
        else
          ref_start = start
        end
      end
      # 操作内容の判定
      if e.status == "cancelled"
        f.puts("#{time}に予定`#{summary}`が削除されました．")
        break
      elsif ((e.updated - e.created) * 24 * 60 * 60).to_i < 1
        f.puts("#{time}に予定`#{e.summary}`が作成されました")
        break
      elsif e.summary != reference["summary"]
        f.puts("#{time}に予定`#{reference['summary']}`のタイトルが`#{e.summary}`に変更されました．")
      elsif e.status != reference["status"]
        f.puts("#{time}に予測結果`#{e.summary}`が確定されました．")
      elsif e.start != ref_start
        f.puts("#{time}に予定`#{e.summary}`の開始時刻が#{start}に変更されました．")
      else
        f.puts("#{time}に予定`#{e.summary}`に操作が行われました．")
      end

      if e.color_id.nil? && e.status == "tentative"
        e.status = "confirmed"
        @service.update_event(@calendar_id, e.id, e)
      end
    end
  end
  puts "ログを出力しました．"
end

def get_events()
  i = 0
  page_token = nil
  begin
    file_name = "origin#{i}"
    result = @service.list_events(@calendar_id, page_token: page_token)
    File.open("result/#{file_name}.json","w") do |f|
      JSON.dump(result, f)
    end
    if result.next_page_token != page_token
      page_token = result.next_page_token
    else
      page_token = nil
    end
    i += 1
  end while !page_token.nil?
end

def tentative_events_delete(recurrence)
  puts "未確定の予定を削除します．"
  page_token = nil
  begin
    result = @service.list_events(@calendar_id,
                                  page_token: page_token,
                                  order_by: "starttime",
                                  single_events: true,
                                  #time_min: Date.today.prev_year(2),
                                  shared_extended_property: "recurrence_name=#{recurrence}"
                                 )
    result.items = result.items.select{|r| r.status == "tentative"}
    result.items.each do |r|
      @service.delete_event(@calendar_id, r.id)
    end
    if result.next_page_token != page_token
      page_token = result.next_page_token
    else
      page_token = nil
    end
  end while !page_token.nil?
  puts "削除しました．"
end

def post_heron_event(events, recurrence)
  puts "再予測結果を登録します．"
  events.split(/\R/).each do |e|
    event = Google::Apis::CalendarV3::Event.new(
      summary: recurrence,
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date: e.chop,
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date: e.chop,
      ),
      color_id: "1",
      status: "tentative",
      extended_properties: Google::Apis::CalendarV3::Event::ExtendedProperties.new(
        shared: {
          recurrence_name: recurrence
        }
      )
    )
    result = @service.insert_event(@calendar_id, event)
  end
  puts "登録が完了しました．"
end

def heron(response)
  response.items.each do |e|
    if e.status != "tentative" && e.extended_properties
      puts "再予測します．少々お待ちください．"
      recurrence = e.extended_properties.shared["recurrence_name"]
      page_token = nil
      command = "./target/release/heron forecast --forecast-year #{Date.today.year}\n"
      arg = ""
      begin
        result = @service.list_events(@calendar_id,
                                      page_token: page_token,
                                      order_by: "starttime",
                                      single_events: true,
                                      #time_min: Date.today.prev_year(2),
                                      shared_extended_property: "recurrence_name=#{e.extended_properties.shared["recurrence_name"]}"
                                     )
        result.items = result.items.select{|r| r.status == "confirmed"}
        result.items.each do |r|
          if r.start.date_time
            date = r.start.date_time.strftime("%Y-%m-%d")
          else
            date = r.start.date.strftime("%Y-%m-%d")
          end
          arg <<  date << "\n"
        end
        if result.next_page_token != page_token
          page_token = result.next_page_token
        else
          page_token = nil
        end
      end while !page_token.nil?
      arg << "EOF\n"
      Dir.chdir(Dir.pwd + "/../heron-Rust/") do
        (status, stdout, stderr) = Open3.capture3(command, :stdin_data=>arg)
        puts "予測が完了しました．"
        tentative_events_delete(recurrence)
        post_heron_event(status, recurrence)

      end
    end
  end
end

before do
  # Initialize the API
  @service = Google::Apis::CalendarV3::CalendarService.new
  @service.client_options.application_name = APPLICATION_NAME
  @service.authorization = authorize

  File.open(CONFIG_PATH) do |f|
    hash = JSON.load(f)
    @calendar_id = hash["calendar_id"]
  end

  get_events()
  
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
    puts "Event is changed in #{@calendar_id}."

    # next_sync_token, expiration が保存された config.json を読み込み
    File.open("config.json") do |f|
      hash = JSON.load(f)
    end

    # 変更された予定を取得
    response = @service.list_events(@calendar_id,
                                    sync_token: hash["next_sync_token"])

    # 変更内容をログに出力
    log_output(response)

    # 変更された予定をファイル保存
    file_store(response)

    # heron の予測結果を確定したなら再予測
    heron(response)

    # config.json の next_sync_token を書き換え
    hash["next_sync_token"] = response.next_sync_token
    File.open("config.json", "w") do |f|
      JSON.dump(hash, f)
    end

  ## チャンネルが作成されたときの処理 
  elsif headers["HTTP_X_GOOG_RESOURCE_STATE"] == "sync"
    # カレンダID を取得
    calendar_id = extract_calendar(headers["HTTP_X_GOOG_RESOURCE_URI"])

    headers.each do |k, v|
      puts "#{k} -> #{v}"
    end

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
