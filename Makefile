# Daily use: `make install` builds Release and installs into /Applications.
APP := SimpleTaskSwitcher
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
PRODUCT := build/Build/Products/Release/$(APP).app

.PHONY: project build install

# Regenerate the Xcode project after editing project.yml or adding files.
project:
	xcodegen generate

build:
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-destination "generic/platform=macOS" -derivedDataPath build -quiet build

install: build
	-pkill -x $(APP)
	rm -rf /Applications/$(APP).app
	ditto $(PRODUCT) /Applications/$(APP).app
	open /Applications/$(APP).app
