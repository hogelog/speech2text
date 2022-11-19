all:
	cd whisper.cpp && make medium && git rev-parse --short HEAD > ../WHISPER_REVISION && cd - && docker build -t speech2text .
