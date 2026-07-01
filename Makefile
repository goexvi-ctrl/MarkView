# Makefile for building and installing MarkView.app
#
# Usage:
#   make            build MarkView.app (Release)
#   make build      same as above
#   make install    build (if needed) and install into /Applications,
#                    then register it with Launch Services
#   make clean      remove local build output

PROJECT_DIR   := .
PROJECT       := $(PROJECT_DIR)/MarkView.xcodeproj
SCHEME        := MarkView
CONFIGURATION := Release
BUILD_DIR     := build
APP_NAME      := MarkView.app
BUILT_APP     := $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(APP_NAME)

INSTALL_DIR   := /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME)

LSREGISTER    := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all build install clean

all: build

build:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath "$(BUILD_DIR)" \
		build

install: build
	sudo rm -rf "$(INSTALLED_APP)"
	sudo cp -R "$(BUILT_APP)" "$(INSTALLED_APP)"
	sudo $(LSREGISTER) -f "$(INSTALLED_APP)"

clean:
	rm -rf "$(BUILD_DIR)"
