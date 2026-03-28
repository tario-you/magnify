APP_NAME := Magnify
DIST_DIR := dist
INSTALL_DIR ?= /Applications

.PHONY: build release package install clean

build:
	swift build

release:
	swift build -c release

package:
	./scripts/package_app.sh

install:
	INSTALL_APP=1 INSTALL_DIR="$(INSTALL_DIR)" ./scripts/package_app.sh

clean:
	rm -rf $(DIST_DIR)
	swift package clean
