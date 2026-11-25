.PHONY: build install package uninstall clean

build:
	@mkdir -p build/PowerSaver.app/Contents/MacOS build/PowerSaver.app/Contents/Resources/scripts
	@cp resources/Info.plist build/PowerSaver.app/Contents/Info.plist
	@cp scripts/*.sh build/PowerSaver.app/Contents/Resources/scripts/
	@chmod +x build/PowerSaver.app/Contents/Resources/scripts/*.sh
	@swiftc -swift-version 5 -O -framework Cocoa -framework IOKit src/PowerSaverApp.swift -o build/PowerSaver.app/Contents/MacOS/PowerSaver
	@codesign --force --sign - build/PowerSaver.app

install:
	@./install.sh

package:
	@./package.sh

uninstall:
	@./uninstall.sh

clean:
	@rm -rf build dist
