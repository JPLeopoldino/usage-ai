PROJECT     := UsageAI.xcodeproj
SCHEME      := UsageAI
DERIVED     := build/DerivedData
DESTINATION := platform=macOS,arch=$(shell uname -m)
APP         := $(DERIVED)/Build/Products/Release/Usage AI.app

.PHONY: generate test build release install run clean

generate:
	xcodegen generate

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) -quiet

build:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) -quiet

release:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) -quiet

# Launch at login records the app's location, so install it to /Applications.
install: release
	-osascript -e 'tell application id "io.github.jpleopoldino.UsageAI" to quit'
	rm -rf "/Applications/Usage AI.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Usage AI.app"
	@sleep 3; pgrep -qf "/Applications/Usage AI.app/Contents/MacOS/Usage AI" \
		&& echo "Usage AI is running. Look for it in the menu bar." \
		|| (echo "Usage AI quit right after launch. See Console > Crash Reports."; exit 1)

run: build
	open "$(DERIVED)/Build/Products/Debug/Usage AI.app"

clean:
	rm -rf build
