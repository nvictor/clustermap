# Clustermap - GitHub Copilot Instructions

**ALWAYS follow these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the information here.**

Clustermap is a native macOS SwiftUI application that visualizes Kubernetes cluster resources using interactive treemaps. The app connects to Kubernetes clusters via standard APIs and presents hierarchical resource data in a zoomable treemap interface.

## Prerequisites and System Requirements

### Required Environment
- **macOS 13.0 or later** - This is a macOS-only application
- **Xcode 15.0 or later** - Required for building from source
- **Swift 6.1.2+** - Included with Xcode
- **Valid kubeconfig file** - For connecting to Kubernetes clusters
- **Kubernetes cluster with Metrics Server** - For CPU/memory metrics (optional, count mode works without)

### CRITICAL: Non-macOS Environments
- **DO NOT attempt to build on Linux/Windows** - The build will fail with "xcodebuild: command not found"
- This is an Xcode project that requires macOS development tools
- Swift compiler alone is insufficient - requires full Xcode toolchain and macOS SDKs

## Working Effectively

### Bootstrap and Build Commands
```bash
# Navigate to project root
cd /path/to/clustermap

# Open project in Xcode (recommended)
open Clustermap/Clustermap.xcodeproj

# OR use command line build
./sh/build.sh
```

### Build Using Xcode (Recommended)
1. Open `Clustermap/Clustermap.xcodeproj` in Xcode
2. Select the "Clustermap" scheme
3. Build and run with ⌘R (Command-R)
4. **BUILD TIME: 2-5 minutes for clean build, 30 seconds for incremental builds**
5. **NEVER CANCEL** builds - Xcode dependency resolution may take 2-3 minutes on first build

### Build Using Command Line
```bash
# Clean build (takes 3-5 minutes, NEVER CANCEL)
xcodebuild clean build -scheme Clustermap -project Clustermap/Clustermap.xcodeproj

# Archive build for release (takes 5-10 minutes, NEVER CANCEL)
xcodebuild -project "Clustermap/Clustermap.xcodeproj" \
  -scheme "Clustermap" \
  -configuration Release \
  -archivePath "build/Clustermap.xcarchive" \
  -destination "platform=macOS,arch=arm64" \
  archive
```

**TIMEOUT SETTINGS:**
- Set timeout to **10+ minutes** for clean builds
- Set timeout to **3+ minutes** for incremental builds
- Set timeout to **15+ minutes** for archive builds

### Dependencies
- **Yams 6.1.0+** - YAML parsing library (automatically resolved by Xcode)
- No manual dependency installation required - Xcode handles Swift Package Manager automatically
- Package is fetched from: https://github.com/jpsim/Yams
- **Important**: First build may take 2-3 minutes to resolve and download Swift packages

## Testing and Validation

### Manual Validation Requirements
**CRITICAL: After making changes, you MUST validate functionality manually:**

1. **Launch the application successfully**
2. **Load a kubeconfig file** - Use the inspector panel to specify path
3. **Connect to a cluster** - Verify cluster resources are fetched
4. **Test visualization modes:**
   - Count mode (works without metrics server)
   - CPU mode (requires metrics server)
   - Memory mode (requires metrics server)
5. **Test interactivity:**
   - Click to zoom into namespaces/deployments
   - Double-click empty space to zoom out
   - Hover for tooltips
6. **Test inspector panel** - View detailed resource information

### Sample Validation Workflow
```bash
# 1. Build the application
./sh/build.sh

# 2. Run the application (via Xcode or build output)
# 3. In the app UI:
#    - Load ~/.kube/config or custom kubeconfig
#    - Switch between Count/CPU/Memory metrics
#    - Navigate the treemap by clicking on sections
#    - Verify inspector panel shows detailed information
```

### Kubernetes Cluster Setup for Testing
Use the provided script to create demo resources:
```bash
# Deploy sample applications to test with
./sh/deploy.sh

# Create service account for testing (if needed)
./sh/createsa.sh
```

### Developer Certificate Management (for maintainers)
```bash
# Export certificate from keychain
./sh/exportkey.sh

# Encode certificate for GitHub secrets
./sh/encodekey.sh
```
**Note**: These scripts are for project maintainers managing code signing certificates.

## App Configuration and Security

### Bundle ID and Code Signing
- **Bundle ID**: `com.mellowfleet.Clustermap`
- **Team ID**: `2DZ6D8C78T`
- **Architecture**: ARM64 (Apple Silicon) primary target
- **Code signing**: Uses Developer ID Application certificate for distribution

### Network Security Configuration
- **ATS Exception**: Allows insecure HTTP to `127.0.0.1` for local Kubernetes API server connections
- **TLS Handling**: Custom `TLSDelegate.swift` for cluster certificate validation
- **Kubeconfig Support**: Handles client certificates, tokens, and custom CA certificates

### Layout and UI Constants
Key configuration values from `Constants.swift`:
- **Minimum node size**: 20x14 pixels (prevents tiny unreadable nodes)
- **Minimum display size**: 40x28 pixels (enforces readability)
- **Padding**: 3 pixels between treemap nodes
- **Color generation**: Deterministic hashing from resource names
- **Sizing metrics**: Count, CPU (millicores), Memory (bytes)

### Key Directories
```
/Clustermap/Clustermap/          # Main Swift source files (~1600 lines)
├── ClustermapApp.swift          # App entry point
├── ContentView.swift            # Main UI view
├── TreemapView.swift            # Core treemap visualization
├── ClusterViewModel.swift       # MVVM view model
├── ClusterService.swift         # Kubernetes API service
├── Models.swift                 # Data models
├── Client.swift                 # HTTP client for K8s API
├── ConfigLoader.swift           # Kubeconfig parsing
├── TreeBuilder.swift            # Tree data structure builder
├── Inspector.swift              # Resource details panel
├── LogView.swift                # Log display component
├── Constants.swift              # Layout constants
└── Assets.xcassets/             # App icons and assets

/.github/workflows/              # GitHub Actions
└── macos-release.yml            # Release build workflow

/sh/                             # Build and deployment scripts
├── build.sh                     # Simple build script
├── deploy.sh                    # Deploy demo K8s resources
└── createsa.sh                  # Create service account
```

### Architecture Overview
- **MVVM Pattern**: Models, ViewModels, Views clearly separated
- **SwiftUI**: Native macOS UI framework
- **Async/Await**: Modern Swift concurrency for API calls
- **TreeNode Structure**: Recursive data structure for treemap visualization

### Frequently Modified Files
When making changes, commonly modified files include:
- `TreemapView.swift` - For visualization changes
- `ClusterViewModel.swift` - For state management
- `ClusterService.swift` - For API integration
- `Models.swift` - For data structure changes

## Common Tasks

### Adding New Kubernetes Resource Types
1. Update `Models.swift` with new Codable structs
2. Modify `ClusterService.swift` to fetch new resources
3. Update `TreeBuilder.swift` to include new resources in tree
4. Test with actual cluster containing the resource type

### Modifying Visualization
1. Update `TreemapView.swift` for rendering changes
2. Modify `Constants.swift` for layout parameters
3. Always test with various cluster sizes (small and large)

### Changing Metrics Calculation
1. Update `TreeBuilder.swift` metric calculation logic
2. Ensure proper handling of missing metrics (fallback to count)
3. Test all three modes: Count, CPU, Memory

### Debugging Connection Issues
1. Check `ConfigLoader.swift` for kubeconfig parsing errors
2. Verify `TLSDelegate.swift` for certificate validation issues
3. Use `LogService.swift` and `ConsoleView.swift` for runtime debugging
4. Test with `127.0.0.1` clusters (minikube/kind) first - ATS exceptions configured

### Performance Tuning
1. Modify layout constants in `Constants.swift`
2. Adjust minimum node sizes if dealing with very large clusters
3. Consider TreeNode structure changes in `Models.swift` for memory optimization
4. Use async operations in `ClusterService.swift` for better responsiveness

## Build Artifacts and Outputs

### Generated Files (in .gitignore)
- `build/` - Build outputs and archives
- `DerivedData/` - Xcode build cache
- `*.app` - Application bundle
- `*.xcarchive` - Archive for distribution

### Release Process
The GitHub Actions workflow (`macos-release.yml`) handles:
1. **Certificate Import and Keychain Setup** - 30 seconds
2. **Xcode Build and Archive** - 5-8 minutes
3. **App Export** - 1-2 minutes  
4. **Notarization with Apple** - 5-10 minutes (can vary significantly)
5. **DMG Creation** - 1 minute
6. **TOTAL RELEASE BUILD TIME: 15-25 minutes, NEVER CANCEL**
7. **Notarization can timeout** - Apple's servers sometimes take 30+ minutes

### GitHub Actions Requirements
- Runs on `macos-latest` runners only
- Requires secrets: `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APP_SPECIFIC_PASSWORD`, `CLUSTERMAP_PROVISIONING_PROFILE`
- Triggered on git tags (`v*`) or manual workflow dispatch

## Troubleshooting

### Common Issues
1. **"xcodebuild: command not found"** - Not on macOS or Xcode not installed
2. **Swift package resolution fails** - Check internet connection, Xcode may need 2-3 minutes
3. **Code signing errors** - Requires valid Apple Developer account for distribution builds
4. **Kubeconfig not found** - Ensure `~/.kube/config` exists or specify custom path in app

### Build Failures
- **Clean and rebuild** - Delete `DerivedData` folder and rebuild
- **Check Xcode version** - Ensure Xcode 15.0+ is installed
- **Verify Swift Package dependencies** - Yams package should auto-resolve

### Runtime Issues
- **No cluster data** - Verify kubeconfig path and cluster connectivity
- **Missing CPU/Memory metrics** - Ensure Kubernetes Metrics Server is deployed
- **UI not responsive** - Check for large clusters (>1000 pods), app may need time to process

## Validation Checklist

Before committing changes:
- [ ] Code builds successfully in Xcode
- [ ] Application launches without crashes
- [ ] Can load and parse kubeconfig files
- [ ] Treemap renders correctly with test cluster
- [ ] All three metric modes work (Count/CPU/Memory)
- [ ] Interactive navigation functions (click/double-click)
- [ ] Inspector panel shows detailed information
- [ ] No console errors during normal operation

## CRITICAL REMINDERS
- **macOS ONLY** - Do not attempt builds on other platforms
- **NEVER CANCEL long-running builds** - Set timeouts of 10+ minutes for builds, 20+ minutes for releases
- **ALWAYS test manually** - Building successfully is not sufficient validation
- **Test with real clusters** - Use provided deployment scripts for consistent testing environment