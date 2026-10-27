GAME ?= games/sample

.PHONY: data art build test all

data:
	python3 tools/csv2json.py $(GAME)/cards.csv

art: data
	python3 tools/make_sheets.py $(GAME)

build:
	python3 tools/bundle.py $(GAME)

test: build
	lua tests/run.lua
	lua tests/fuzz.lua
	python3 tools/bundle.py games/lantern -o build/lantern/Global.lua
	lua tests/lantern.lua

all: art test
