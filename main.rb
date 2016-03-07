# coding: utf-8
# ライブラリ
require "sinatra"
require "slack"
require "redis"
require "tumblr_client"
require "json"
require "./settings.rb"

# ----- TUMBLR: 認証 -----
Tumblr.configure do |config|
  config.consumer_key = TUMBLR_CONSUMER_KEY
  config.consumer_secret = TUMBLR_CONSUMER_SECRET
  config.oauth_token = TUMBLR_OAUTH_TOKEN
  config.oauth_token_secret = TUMBLR_OAUTH_TOKEN_SECRET
end


# ----- SLACK: 認証 -----
Slack.configure {|config| config.token = SLACK_TOKEN }


# ----- REDIS: 初期化 -----
if ENV["REDISTOGO_URL"]
  uri = URI.parse(ENV["REDISTOGO_URL"])
  @@post_data = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
else
  @@post_data = Redis.new(:host => "127.0.0.1", :port => "6379")
end


# ----- TUMBLR: メソッド -----
def post_text_tumblr (title, body, tags)
  tumblr_client = Tumblr::Client.new
  tumblr_client.text(TUMBLR_URL, {:title => title, :body => body, :tags => tags})
end

def post_photo_tumblr (url, caption, tags)
  tumblr_client = Tumblr::Client.new
  tumblr_client.photo(TUMBLR_URL, {:link => url, :source=> url, :caption=> caption, :tags => tags})
end

def post_binary_photo_tumblr (data, caption, tags) # 動いてない…
  tumblr_client = Tumblr::Client.new
  tumblr_client.photo(TUMBLR_URL, {:data => data, :caption=> caption, :tags => tags})
end

def post_video_tumblr (url, caption, tags)
  tumblr_client = Tumblr::Client.new
  tumblr_client.video(TUMBLR_URL, {:embed=> url, :caption=> caption, :tags => tags})
end

def post_link_tumblr (title, url, description, tags)
  tumblr_client = Tumblr::Client.new
  tumblr_client.link(TUMBLR_URL, {:title => title, :url => url, :description => description, :tags => tags})
end

def post_quote_tumblr (quote, source, tags)
  tumblr_client = Tumblr::Client.new
  tumblr_client.quote(TUMBLR_URL, {:quote => quote, :source => source, :tags => tags})
end

def format_data(data)
  case data[:type]
    when "text"
      _b = JSON.parse(data[:data])["text"]
      _b.gsub!("<@" + SLACK_BOT_ACCOUNT + ">: ", "")
      _b.gsub!("<@" + SLACK_BOT_ACCOUNT + ">", "")
      body = _b.gsub(":", "")
      title = data[:title]
      tags = data[:tags].split(",")
      post_text_tumblr(title, body, tags)
    when "photo"
      # バイナリでデータを渡せばできるらしい？（未実装）
      if JSON.parse(data[:data])["file"]
        binary = JSON.parse(data[:data])["file"]["url_private"]
        tags = data[:tags].split(",")
        caption = data[:caption]
        post_binary_photo_tumblr(binary, caption, tags)
      else
        _u = JSON.parse(data[:data])["text"]
        url = _u.match(%r{https?://[\w/:%#\$&\?\(\)~\.=\+\-]+}).to_s
        tags = data[:tags].split(",")
        caption = data[:caption]
        post_photo_tumblr(url, caption, tags)
      end
    when "video"
      _u = JSON.parse(data[:data])["text"]
      url = _u.match(%r{https?://[\w/:%#\$&\?\(\)~\.=\+\-]+}).to_s
      tags = data[:tags].split(",")
      caption = data[:caption]
      post_video_tumblr(url, caption, tags)
    when "link"
      title = data[:title]
      _u = JSON.parse(data[:data])["text"]
      url = _u.match(%r{https?://[\w/:%#\$&\?\(\)~\.=\+\-]+}).to_s
      description = data[:description]
      tags = data[:tags].split(",")
      post_link_tumblr(title, url, description, tags)
    when "quote"
      _q = JSON.parse(data[:data])["text"]
      _q.gsub!("<@" + SLACK_BOT_ACCOUNT + ">: ", "")
      _q.gsub!("<@" + SLACK_BOT_ACCOUNT + ">", "")
      quote = _q.gsub(":", "")
      source = data[:source]
      tags = data[:tags].split(",")
      post_quote_tumblr(quote, source, tags)
    else
      try_again()
  end
end

# ----- REDIS: リセット -----
def reset_data
  @@post_data.flushall
end

# ----- SLACK: 出力メッセージ -----
def say (text)
  params = {
    token: SLACK_TOKEN,
    channel: SLACK_CHANNEL,
    as_user: true,
    text: text,
  }
  Slack.chat_postMessage(params)
end

def msg_question_type
  say("タイプを入力してください：text / photo / video / link / quote")
end

def msg_question_tags
  say("タグを入力してください：tags, tags")
end

def msg_question_option
  case @@post_data["type"]
    when "text"
      say("タイトルを入力してください")
    when "photo", "video"
      say("キャプションを入力してください")
    when "link"
      say("タイトルを入力してください")
    when "quote"
      say("ソースを入力してください")
    else
      try_again("type")
  end
end

def msg_post_done
  say("ポストを投稿しました！")
end

def msg_error
  say("エラーです")
end

def try_again
  @@post_data.flushall
  say("最初からやりなおしてください")
end


# ----- METHOD: タグ -----
def tag_division (_t)
  _t.gsub!("<@" + SLACK_BOT_ACCOUNT + ">", "")
  text = _t.gsub(":", "")
  # タグに分割
  if text.include?(",")
    text.gsub!(" ", "")
    text.gsub!("#", "")
    tags = text
  elsif text.include?(" ")
    tags = text.gsub(" ", ",")
  else
    tags = text
  end
  tags
end

def tag_check (_t)
  _t.gsub!("<@" + SLACK_BOT_ACCOUNT + ">", "")
  _t.gsub!(":", "")
  type = _t.gsub(" ", "")
  case type
    when "text", "txt", "t"
      "text"
    when "photo", "p", "img"
      "photo"
    when "video", "v"
      "video"
    when "link", "l"
      "link"
    when "quote", "q"
      "quote"
    else
      try_again()
  end
end


# ----- METHOD: オプションの追加 -----
def add_option (_d)
  _d.gsub!("<@" + SLACK_BOT_ACCOUNT + ">", "")
  _d.gsub!(":", "")
  data = _d.gsub(" ", "")
  case @@post_data[:type]
    when "text"
      if !@@post_data[:title]
        @@post_data[:title] = data
        @@post_data[:done] = true
      end
    when "photo", "video"
      if !@@post_data[:caption]
        @@post_data[:caption] = data
        @@post_data[:done] = true
      end
    when "link"
      if !@@post_data[:title]
        @@post_data[:title] = data
        say("ディスクリプションを入力してください")
      else
        @@post_data[:description] = data
        @@post_data[:done] = true
      end
    when "quote"
      if !@@post_data[:source]
        _s = data
        source = _s.match(%r{https?://[\w/:%#\$&\?\(\)~\.=\+\-]+})
        @@post_data[:source] = source
        @@post_data[:done] = true
      end
    else
      try_again()
  end
end


# ----- ルーティング -----
post '/webhook' do

  if params[:user_id] == SLACK_USER_ID

    # :dataを持っていなかったら
    if !@@post_data[:data]
      @@post_data[:data] = params.to_json
      msg_question_type() # 次の質問

    # :typeを持っていなかったら
    elsif !@@post_data[:type]
      @@post_data[:type] = tag_check(params[:text])
      try_again() if @@post_data[:type] == "error" # エラーが出たらやり直し
      msg_question_tags() # 次の質問

    # :tagsを持っていなかったら
    elsif !@@post_data[:tags]
      @@post_data[:tags] = tag_division(params[:text])
      msg_question_option()

    # :typeを持っていたら
    elsif @@post_data[:type]
      add_option(params[:text])
      if @@post_data[:done]
        format_data(@@post_data) # フォーマットしてポストする
        reset_data()
        msg_post_done()
      end

    # その他
    else
      msg_error()
    end

  end

end
