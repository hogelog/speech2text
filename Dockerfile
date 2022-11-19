FROM public.ecr.aws/docker/library/ruby:3.1-slim-bullseye AS build

RUN apt-get update && apt-get install -y --no-install-recommends build-essential
WORKDIR /src
COPY whisper.cpp/ /src/
RUN make clean && make

COPY Gemfile Gemfile.lock /src/
RUN bundle install

FROM public.ecr.aws/docker/library/ruby:3.1-slim-bullseye

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/main /app/main
COPY whisper.cpp/models/ggml-medium.bin /app/ggml-medium.bin

COPY --from=build /usr/local/bundle/ /usr/local/bundle/

COPY Gemfile Gemfile.lock web.rb worker.rb WHISPER_REVISION /app/

CMD ["bundle", "exec", "ruby", "web.rb"]
