.PHONY: ffi header xcode build test clean lint lint-rust lint-swift

# Build Rust FFI static library (vitals-ffi is a member of the root
# Cargo workspace, so this runs from repo root, not app/vitals-ffi)
ffi:
	cd .. && cargo build --release -p vitals-ffi

# Generate C header (happens automatically during cargo build via build.rs)
header: ffi

# Generate Xcode project from project.yml, then refresh the pointer
# sourcekit-lsp uses to find it. Without a current buildServer.json the
# editor cannot read the .xcodeproj at all: it parses each file in
# isolation and reports every project-owned symbol as "cannot find X in
# scope" while framework symbols still resolve. Regenerating the project
# without regenerating this leaves it stale, so the two belong together.
# Skipped with a note where the tool isn't installed (CI never needs it).
xcode: header
	xcodegen generate
	@command -v xcode-build-server >/dev/null 2>&1 \
		&& xcode-build-server config -project VitalsApp.xcodeproj -scheme VitalsApp >/dev/null \
		|| echo "note: xcode-build-server not installed, skipping buildServer.json (editor indexing only)"

# Build the macOS app via xcodebuild. ONLY_ACTIVE_ARCH restricts this to
# the host's architecture — vitals-ffi is only cargo-built for the host
# triple here, unlike CI's release workflow, which cross-compiles it per
# arch and passes -arch explicitly to xcodebuild.
build: xcode
	xcodebuild -project VitalsApp.xcodeproj -scheme VitalsApp -configuration Release ONLY_ACTIVE_ARCH=YES build

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
