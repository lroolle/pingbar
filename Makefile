BUILD_DIR = $(CURDIR)/build
DERIVED_DATA_DIR = $(BUILD_DIR)/DerivedData
VERSION ?=
XCODEBUILD ?= xcodebuild
XCODEGEN ?= xcodegen

.PHONY: doctor project build test run ci release-dmg clean

doctor:
	./scripts/doctor.sh

project:
	$(XCODEGEN) generate

build: doctor project
	$(XCODEBUILD) -project PingBar.xcodeproj -scheme PingBar -configuration Debug \
		-derivedDataPath $(DERIVED_DATA_DIR) \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR) build

test: doctor project
	$(XCODEBUILD) test -project PingBar.xcodeproj -scheme PingBar -configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED_DATA_DIR) \
		-enableCodeCoverage YES

run: build
	open -n $(BUILD_DIR)/PingBar.app

ci: doctor test build

release-dmg: doctor project
	VERSION="$(VERSION)" ./scripts/package-dmg.sh

clean:
	-$(XCODEBUILD) -project PingBar.xcodeproj -scheme PingBar clean
	rm -rf $(BUILD_DIR)
