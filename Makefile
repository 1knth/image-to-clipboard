.PHONY: build test run clean icon

APP := build/Clippy.app

build:
	bash scripts/build.sh

test:
	bash scripts/test.sh

run: build
	open $(APP)

icon:
	bash scripts/make-icon.sh

clean:
	rm -rf build
