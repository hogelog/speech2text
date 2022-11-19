require "json"

require "aws-sdk-s3"

require "sinatra"
require "kaminari/sinatra"

if development?
  require "sinatra/reloader"
  set :bind, "0.0.0.0"
end

WHISPER_REVISION = File.read("/app/WHISPER_REVISION").chomp

S3_BUCKET = ENV.fetch("S3_BUCKET")
S3_PREFIX = ENV.fetch("S3_PREFIX")
S3_ENDPOINT = ENV["S3_ENDPOINT"]
S3_ACCESS_KEY_ID = ENV["S3_ACCESS_KEY_ID"]
S3_SECRET_ACCESS_KEY = ENV["S3_SECRET_ACCESS_KEY"]
S3_FORCE_PATH_STYLE = !!ENV["S3_FORCE_PATH_STYLE"]

class Storage

  def initialize
    @s3 = Aws::S3::Client.new(endpoint: S3_ENDPOINT, access_key_id: S3_ACCESS_KEY_ID, secret_access_key: S3_SECRET_ACCESS_KEY, force_path_style: S3_FORCE_PATH_STYLE)
    @s3_queue_prefix = S3_PREFIX + "queue/"
    @s3_done_prefix = S3_PREFIX + "done/"
  end

  def queue_list(token: nil)
    list(@s3_queue_prefix, token:)
  end

  def done_list(token: nil)
    list(@s3_done_prefix, token:)
  end

  def list(prefix, token: nil)
    @s3.list_objects_v2(bucket: S3_BUCKET, prefix: prefix, continuation_token: token)
  end

  def view(key)
    response = @s3.get_object(bucket: S3_BUCKET, key: key)
    JSON.parse(response.body.string, symbolize_names: true)
  end

  def enqueue(name, tempfile)
    key = @s3_queue_prefix + name
    @s3.put_object(bucket: S3_BUCKET, key: key, body: tempfile)
  end
end

storage = Storage.new

get "/" do
  queue_response = storage.queue_list
  @queue_objects = queue_response.contents.to_a

  @done_response = storage.done_list(token: params[:token])
  @done_objects = @done_response.contents.select{ _1.key.end_with?(".json") }.to_a

  erb <<HTML
<html lang="en">
<head>
<title>speech2text</title>
</head>
<body>
  <h1>speech2text</h1>

  <h2>New</h2>
  <form action="/" method="post" enctype="multipart/form-data">
    <input type="file" name="file">
    <input type="submit">
  </form>

  <h2>Queue</h2>
  <ul>
    <% @queue_objects.each do |object| %>
    <li><a href="view/<%= object.key %>"><%= object.key %></a></li>
    <% end %>
  </ul>

  <h2>Done</h2>
  <ul>
    <% @done_objects.each do |object| %>
    <li><a href="view/<%= object.key %>"><%= object.key %></a></li>
    <% end %>
  </ul>
  <% if @done_response.next_continuation_token %>
  <a href="/?token=<%= @done_response.next_continuation_token %>">Next</a>
  <% end %>
  <a href="https://github.com/ggerganov/whisper.cpp">Powered by whisper.cpp (revision: <%= WHISPER_REVISION %>)</a>
</body>
</html>
HTML
end

post "/" do
  storage.enqueue(params[:file][:filename], params[:file][:tempfile])
  redirect "/"
end

get "/view/*" do
  @key = params[:splat].first
  @data = storage.view(@key)

  erb <<HTML
<html lang="en">
<head>
<title><%= @key %> - speech2text</title>
</head>
<body>
  <h1><%= @key %> - speech2text</h1>
  <h2>Text</h2>
  <pre><%= @data[:text] %></pre>
  <h2>Text with timings</h2>
  <pre><%= @data[:text_with_timings] %></pre>
</body>
</html>
HTML
end
