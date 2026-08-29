APP := SoundEnhancer.app
PREFIX ?= $(HOME)/Applications

.PHONY: build app driver install run test clean dist

build:
	swift build -c release

driver:
	./Scripts/build-driver.sh

app: build
	./Scripts/build-app.sh

dist:
	@test -n "$$CODE_SIGN_IDENTITY" || { echo "Error: CODE_SIGN_IDENTITY is required for distribution"; exit 1; }
	$(MAKE) app
	./Scripts/notarize.sh

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
