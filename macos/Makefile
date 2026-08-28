CC ?= clang
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic -Werror -I../core/include
LDFLAGS += -framework CoreFoundation -framework IOKit -framework ApplicationServices

TARGET = trackpoint-scroll-macos
SOURCES = trackpoint-scroll-macos.c ../core/src/engine.c ../core/src/profiles.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -lm -o $@

clean:
	rm -f $(TARGET)
