require "json"
require "open3"
require "tempfile"
require "tmpdir"

require "aws-sdk-s3"

S3_REGION = ENV.fetch("S3_REGION")
S3_BUCKET = ENV.fetch("S3_BUCKET")
S3_PREFIX = ENV.fetch("S3_PREFIX")
S3_ENDPOINT = ENV["S3_ENDPOINT"]
S3_ACCESS_KEY_ID = ENV["S3_ACCESS_KEY_ID"]
S3_SECRET_ACCESS_KEY = ENV["S3_SECRET_ACCESS_KEY"]
S3_FORCE_PATH_STYLE = !!ENV["S3_FORCE_PATH_STYLE"]

class Transcripter
  class Result
    attr_reader :raw_result, :timing_lines, :text_lines

    def initialize(raw_result)
      @raw_result = raw_result
      @timing_lines = raw_result.strip.lines.map(&:chomp)
      @text_lines = @timing_lines.map { _1.sub(/\[[\d:\. \->]+\]\s+/, "") }
    end
  end

  def transcript(voicefile)
    output = convert_wavfile(voicefile) do |wavfile|
      command = ["/app/main", "-m", "ggml-medium.bin", "-l", "ja", "-f", wavfile]
      puts(command.join(" "))
      output, error, status = Open3.capture3(*command)
      STDERR.puts(error)
      unless status.success?
        exit status.to_i
      end
      output
    end

    Result.new(output)
  end

  def convert_wavfile(voicefile)
    Dir.mktmpdir do |tmpdir|
      wavfile = File.join(tmpdir, "voice.wav")
      command = ["ffmpeg", "-i", voicefile, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wavfile]
      puts(command.join(" "))
      system(*command, exception: true)
      yield(wavfile)
    end
  end
end

class Worker
  def initialize
    @s3 = Aws::S3::Client.new(region: S3_REGION, endpoint: S3_ENDPOINT, access_key_id: S3_ACCESS_KEY_ID, secret_access_key: S3_SECRET_ACCESS_KEY, force_path_style: S3_FORCE_PATH_STYLE)
    @transcripter = Transcripter.new
    @s3_queue_prefix = S3_PREFIX + "queue/"
    @s3_done_prefix = S3_PREFIX + "done/"
  end

  def run
    response = @s3.list_objects_v2(bucket: S3_BUCKET, prefix: @s3_queue_prefix)
    response.contents.each do |content|
      object = @s3.get_object(bucket: S3_BUCKET, key: content.key)
      Tempfile.open do |voicefile|
        IO.copy_stream(object.body, voicefile)
        voicefile.flush
        result = @transcripter.transcript(voicefile.path)
        puts result.inspect
        json = JSON.generate(text: result.text_lines.join("\n"), text_with_timings: result.timing_lines.join("\n"))

        result_key = @s3_done_prefix + Time.now.strftime("%Y-%m-%d/%H%M%S_") + File.basename(content.key)
        json_key = result_key + ".json"
        @s3.put_object(bucket: S3_BUCKET, key: json_key, body: json)
        @s3.delete_object(bucket: S3_BUCKET, key: content.key)
      end
    end
  end
end

if __FILE__ == $0
  Worker.new.run
end
