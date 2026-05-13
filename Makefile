BUILD_DIR = $(CURDIR)/build

.PHONY: project build run clean

project:
	xcodegen generate

build: project
	xcodebuild -project NetMon.xcodeproj -scheme NetMon -configuration Debug \
		CONFIGURATION_BUILD_DIR=$(BUILD_DIR) build

run: build
	open $(BUILD_DIR)/NetMon.app

clean:
	xcodebuild -project NetMon.xcodeproj -scheme NetMon clean
	rm -rf $(BUILD_DIR)
