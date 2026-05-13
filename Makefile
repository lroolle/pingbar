BUILD_DIR = $(CURDIR)/build

.PHONY: project build run clean

project:
	xcodegen generate

build: project
	xcodebuild -project PingBar.xcodeproj -scheme PingBar -configuration Debug \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR) build

run: build
	open $(BUILD_DIR)/PingBar.app

clean:
	xcodebuild -project PingBar.xcodeproj -scheme PingBar clean
	rm -rf $(BUILD_DIR)
