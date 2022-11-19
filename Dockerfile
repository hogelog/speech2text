FROM public.ecr.aws/docker/library/debian:bullseye-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends g++ make
WORKDIR /src
COPY whisper.cpp/ /src/

RUN make clean && make

FROM public.ecr.aws/docker/library/ruby:3.1-slim-bullseye

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg build-essential && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/main /app/main
COPY whisper.cpp/models/ggml-medium.bin /app/ggml-medium.bin

COPY Gemfile Gemfile.lock /app/
RUN bundle install

COPY web.rb worker.rb WHISPER_REVISION /app/

CMD ["bundle", "exec", "ruby", "web.rb"]
