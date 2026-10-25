APP := SoundEnhancer.app
PREFIX ?= $(HOME)/Applications

.PHONY: build app driver install run test clean dist dmg release

build:
	swift build -c release

driver:
	./Scripts/build-driver.sh

app: build
	./Scripts/build-app.sh

dmg: app
	./Scripts/make-dmg.sh

dist:
	@test -n "$$CODE_SIGN_IDENTITY" || { echo "Error: CODE_SIGN_IDENTITY is required for distribution"; exit 1; }
	$(MAKE) app
	./Scripts/notarize.sh

release:
	@VERSION="$$(./Scripts/version.sh)"; \
	if [ "$$VERSION" = "0.0.0" ]; then \
		echo "Error: no git tag found. Tag the release first (e.g. git tag v1.1.0)"; exit 1; \
	fi; \
	test -n "$$CODE_SIGN_IDENTITY" || { echo "Error: CODE_SIGN_IDENTITY is required"; exit 1; }; \
	$(MAKE) dist; \
	gh release create "v$$VERSION" "dist/SoundEnhancer-$$VERSION.dmg" \
		--title "SoundEnhancer $$VERSION" --generate-notes

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
