.PHONY: ffi header xcode build test clean lint lint-rust lint-swift

# Build Rust FFI static library (vitals-ffi is a member of the root
# Cargo workspace, so this runs from repo root, not app/vitals-ffi)
ffi:
	cd .. && cargo build --release -p vitals-ffi

# Generate C header (happens automatically during cargo build via build.rs)
header: ffi

# Generate Xcode project from project.yml
xcode: header
	xcodegen generate

# Build the macOS app via xcodebuild
build: xcode
	xcodebuild -project VitalsApp.xcodeproj -scheme VitalsApp -configuration Release build

# Run the Swift test suite
test: xcode
	xcodebuild -project VitalsApp.xcodeproj -scheme VitalsApp -configuration Debug test

# Lint all code (Rust + Swift)
lint: lint-rust lint-swift

# Rust: format check + clippy
lint-rust:
	cd .. && cargo fmt --check -p vitals-ffi
	cd .. && cargo clippy -p vitals-ffi --all-targets -- -D warnings

# Swift: SwiftLint (auto-detect Xcode for SourceKit)
lint-swift:
	@if [ -z "$$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then \
		DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --strict; \
	else \
		swiftlint lint --strict; \
	fi

clean:
	cd .. && cargo clean -p vitals-ffi
	rm -rf DerivedData build VitalsApp.xcodeproj
