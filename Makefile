.PHONY: build test app install run icon dmg clean

build:
	swift build

test:
	swift test

app:
	scripts/build-app.sh

install:
	scripts/build-app.sh --install

run:
	scripts/build-app.sh --open

icon:
	scripts/make-icon.sh

dmg: app
	scripts/make-dmg.sh

clean:
	rm -rf build .build
