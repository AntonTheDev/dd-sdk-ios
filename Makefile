all: tools dependencies xcodeproj-httpservermock templates
.PHONY : tools

tools:
		@echo "⚙️  Installing tools..."
		@brew list swiftlint &>/dev/null || brew install swiftlint
		@echo "OK 👌"

dependencies:
		@echo "⚙️  No dependencies required, skipping..."

xcodeproj-httpservermock:
		@echo "⚙️  Generating 'HTTPServerMock.xcodeproj'..."
		@cd instrumented-tests/http-server-mock/ && swift package generate-xcodeproj
		@echo "OK 👌"

templates:
		@echo "⚙️  Installing Xcode templates..."
		./tools/xcode-templates/install-xcode-templates.sh
		@echo "OK 👌"

# Tests if current branch ships a valid SPM package.
test-spm:
		@cd dependency-manager-tests/spm && $(MAKE)

# Tests if current branch ships a valid Carthage project.
test-carthage:
		@cd dependency-manager-tests/carthage && $(MAKE)

# Tests if current branch ships a valid Cocoapods project.
test-cocoapods:
		@cd dependency-manager-tests/cocoapods && $(MAKE)

# Generate RUM data models from rum-events-format JSON Schemas
generate-rum-models:
		@echo "⚙️  Generating RUM models..."
		./tools/generate-models/run.sh generate
		@echo "OK 👌"

# Generate api-surface files for Datadog and DatadogObjc.
api-surface:
		@cd tools/api-surface/ && swift build --configuration release
		@echo "Generating api-surface-swift"
		./tools/api-surface/.build/x86_64-apple-macosx/release/api-surface workspace --workspace-name Datadog.xcworkspace --scheme Datadog --path . > api-surface-swift
		@echo "Generating api-surface-objc"
		./tools/api-surface/.build/x86_64-apple-macosx/release/api-surface workspace --workspace-name Datadog.xcworkspace --scheme DatadogObjc --path . > api-surface-objc

bump:
		@read -p "Enter version number: " version;  \
		echo "// GENERATED FILE: Do not edit directly\n\ninternal let sdkVersion = \"$$version\"" > Sources/Datadog/Versioning.swift; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDK.podspec.src > DatadogSDK.podspec; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDKObjc.podspec.src > DatadogSDKObjc.podspec; \
		git add . ; \
		git commit -m "Bumped version to $$version"; \
		echo Bumped version to $$version

ship:
		pod spec lint DatadogSDK.podspec
		pod spec lint DatadogSDKObjc.podspec
		pod trunk push DatadogSDK.podspec
		pod trunk push DatadogSDKObjc.podspec
