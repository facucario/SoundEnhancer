APP := SoundEnhancer.app
PREFIX ?= $(HOME)/Applications

.PHONY: build app driver install run test clean

build:
	swift build -c release

driver:
	./Scripts/build-driver.sh

app: build
	./Scripts/build-app.sh

install: app
	rm -rf "$(PREFIX)/SoundEnhancer.app"
	cp -R "$(APP)" "$(PREFIX)/"
	@echo "Installed to $(PREFIX)/SoundEnhancer.app"

run:
	swift run SoundEnhancer

test:
	swift test

clean:
	swift package clean
	rm -rf "$(APP)" SoundEnhancerDriver.driver
