APP_NAME := Magnify
DIST_DIR := dist
INSTALL_DIR ?= /Applications
RESET_TCC ?= 1
RELAUNCH_APP ?= 1

.PHONY: build release package install clean

build:
	swift build

release:
	swift build -c release

package:
	./scripts/package_app.sh

install:
	INSTALL_APP=1 INSTALL_DIR="$(INSTALL_DIR)" RESET_TCC="$(RESET_TCC)" RELAUNCH_APP="$(RELAUNCH_APP)" ./scripts/package_app.sh

clean:
	rm -rf $(DIST_DIR)
	swift package clean
