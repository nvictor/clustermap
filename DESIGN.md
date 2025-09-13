# Clustermap Design Document

This document describes the architecture, design decisions, and implementation details of the Clustermap application.

## Overview

Clustermap is a native macOS application that visualizes Kubernetes cluster resources using treemap visualization. The application fetches data from Kubernetes clusters via the standard API and presents it in an interactive, hierarchical treemap interface.

## Architecture

### High-Level Architecture

```
┌─────────────────┐    ┌────────────────────┐    ┌──────────────────┐
│   SwiftUI Views │────│   ViewModels       │────│    Services      │
│                 │    │                    │    │                  │
│ • TreemapView   │    │ • ClusterViewModel │    │ • ClusterService │
│ • ContentView   │    │                    │    │ • Client         │
│ • Inspector     │    │                    │    │ • ConfigLoader   │
└─────────────────┘    └────────────────────┘    └──────────────────┘
                                │                         │
                                │                         │
                        ┌───────────────────┐    ┌─────────────────┐
                        │     Models        │    │   External      │
                        │                   │    │                 │
                        │ • TreeNode        │    │ • Kubernetes    │
                        │ • KubeResources   │    │   API Server    │
                        │ • ClusterSnapshot │    │ • Kubeconfig    │
                        └───────────────────┘    └─────────────────┘
```

### MVVM Pattern

The application follows the Model-View-ViewModel (MVVM) architectural pattern:

- **Models**: Pure data structures representing Kubernetes resources and application state
- **ViewModels**: Business logic, state management, and coordination between views and services  
- **Views**: SwiftUI components responsible for rendering the UI and handling user interactions
- **Services**: Data layer handling Kubernetes API communication and data processing

## Core Components

### 1. Data Models (`Models.swift`)

#### TreeNode
The fundamental data structure for treemap visualization:

```swift
struct TreeNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let value: Double
    let children: [TreeNode]
    var isLeaf: Bool { children.isEmpty }
}
```

**Design Rationale**:
- Recursive structure naturally represents hierarchical data
- `Identifiable` enables efficient SwiftUI updates
- `Hashable` enables set operations and caching
- `value` represents the sizing metric (count, CPU, memory)

#### Kubernetes Resource Models
Direct mappings to Kubernetes API objects:

- `KubeNamespace`: Cluster namespaces
- `KubePod`: Pod resources with specs and status
- `KubeDeployment`: Deployment resources with replicas and templates
- `PodMetrics`: Resource usage metrics from metrics-server

**Design Decisions**:
- Use `Codable` for automatic JSON parsing
- Include only necessary fields to minimize memory footprint
- Separate specs, status, and metadata following Kubernetes patterns

#### ClusterSnapshot
Aggregates all cluster data for processing:

```swift
struct ClusterSnapshot {
    let namespaces: [KubeNamespace]
    let deploymentsByNS: [String: [KubeDeployment]]
    let podsByNS: [String: [KubePod]]
    let metricsByNS: [String: [PodMetrics]]
}
```

This design enables:
- Atomic cluster state capture
- Efficient namespace-based data organization
- Immutable data flow

### 2. Services Layer

#### ClusterService (`ClusterService.swift`)

Orchestrates data fetching and tree building:

```swift
func fetchTree(from path: String, metric: SizingMetric) async -> Result<TreeNode, Error>
```

**Key Features**:
- Async/await for modern concurrency
- Error handling with `Result` type
- Concurrent namespace data fetching with `TaskGroup`

**Concurrency Strategy**:
```swift
try await withThrowingTaskGroup(of: NamespaceResources.self) { group in
    for namespace in namespaces {
        group.addTask {
            try await fetchResourcesForNamespace(namespace.metadata.name, using: client)
        }
    }
    // Process results...
}
```

This approach:
- Maximizes parallelism when fetching namespace data
- Maintains data consistency
- Provides graceful error handling per namespace

#### Client (`Client.swift`)

Low-level Kubernetes API client:

**Design Principles**:
- Protocol-based for testability
- URL-based API construction
- Custom TLS handling for cluster certificates
- Structured error handling

#### ConfigLoader (`ConfigLoader.swift`)

Handles kubeconfig parsing and credential management:

**Features**:
- YAML parsing with Yams library
- Multi-context support
- Certificate and token authentication
- Secure credential storage

### 3. Tree Building (`TreeBuilder.swift`)

Transforms cluster data into treemap structure:

```
Cluster Root
├── Namespace A
│   ├── Deployment 1
│   │   ├── Pod 1
│   │   └── Pod 2
│   └── Deployment 2
│       └── Pod 3
└── Namespace B
    └── Deployment 3
        └── Pod 4
```

**Metric Calculations**:

- **Count**: Number of pods/containers
- **CPU**: Millicores from requests/usage  
- **Memory**: Bytes from requests/usage

**Design Decisions**:
- Build complete tree structure upfront for UI performance
- Filter empty namespaces/deployments
- Use doubles for metric values to support fractional resources

### 4. View Layer

#### TreemapView (`TreemapView.swift`)

The core visualization component implementing recursive treemap rendering:

**Algorithm**: Squarified treemap layout for optimal aspect ratios

**Key Features**:
- Recursive SwiftUI views for each tree level
- Color coding based on node names (deterministic hashing)
- Hover effects and click handling
- Responsive layout with minimum size constraints

**Layout Constants** (`Constants.swift`):
```swift
struct LayoutConstants {
    static let minNodeWidth: CGFloat = 20
    static let minNodeHeight: CGFloat = 14
    static let minDisplayWidth: CGFloat = 40
    static let minDisplayHeight: CGFloat = 28
    static let padding: CGFloat = 3
}
```

#### ContentView (`ContentView.swift`)

Main application view coordinating:
- Treemap display
- Inspector panel
- Toolbar actions
- Initial data loading

### 5. State Management

#### ClusterViewModel (`ClusterViewModel.swift`)

Central state management using `@Published` properties:

```swift
@Published var metric: SizingMetric = .count { didSet { reload() } }
@Published var root: TreeNode = TreeNode(name: "Welcome", value: 1, children: [])
@Published var maxLeafValue: Double = 1.0
@Published var selectedPath: [UUID]?
```

**State Flow**:
1. User changes metric → `reload()` triggered
2. `ClusterService` fetches new data
3. `TreeBuilder` creates new tree structure
4. UI automatically updates via `@Published` bindings

## Data Flow

### Startup Sequence

1. **App Launch**: `ClustermapApp.swift` initializes `ClusterViewModel`
2. **Config Loading**: Default kubeconfig path loaded from user defaults
3. **Initial Load**: `ContentView` triggers `loadCluster()` on appearance
4. **Data Fetching**: Parallel namespace resource fetching
5. **Tree Building**: Transform cluster data to treemap structure
6. **UI Rendering**: SwiftUI renders treemap visualization

### User Interaction Flow

```
User Action → ViewModel Update → Service Call → Data Processing → UI Update
```

Example: Changing Metric
1. User selects "CPU" from dropdown
2. `metric` property updated in ViewModel
3. `didSet` triggers `reload()`
4. `ClusterService.fetchTree()` called with new metric
5. `TreeBuilder` recalculates values
6. New `TreeNode` published
7. `TreemapView` re-renders with new sizing

## Performance Considerations

### Memory Management

- **Immutable Data Structures**: Prevent accidental mutations and enable sharing
- **Lazy Loading**: Only load visible namespace data initially
- **Value Types**: Structs over classes where possible for better memory layout

### Rendering Performance

- **SwiftUI Optimization**: Use `@StateObject`, `@ObservedObject`, and `@EnvironmentObject` appropriately
- **View Identity**: Stable IDs prevent unnecessary view recreation
- **Layout Caching**: Pre-calculate treemap layouts to avoid real-time computation

### Network Efficiency

- **Concurrent Requests**: Parallel namespace fetching reduces total load time
- **Request Batching**: Group related API calls where possible
- **Error Isolation**: Per-namespace error handling prevents total failure

## Security Considerations

### Credential Handling

- **No Plaintext Storage**: Credentials loaded from kubeconfig at runtime
- **TLS Verification**: Custom delegate for cluster certificate validation  
- **Minimal Permissions**: Only requires read access to cluster resources

### Network Security

- **HTTPS Only**: All cluster communication over TLS
- **Certificate Pinning**: Support for custom CA certificates
- **Token Refresh**: Handle authentication token expiration gracefully

## Error Handling Strategy

### Layered Error Handling

1. **Network Layer**: HTTP errors, connection failures
2. **API Layer**: Kubernetes API errors, authorization failures  
3. **Data Layer**: Parsing errors, missing metrics
4. **UI Layer**: User-friendly error messages

### Graceful Degradation

- **Missing Metrics**: Fall back to count-based visualization
- **Partial Data**: Show available namespaces even if some fail
- **Network Issues**: Retain last successful data with error indicators

## Testing Strategy

### Unit Testing Approach

- **Model Testing**: Verify Codable implementations and data transformations
- **Service Testing**: Mock Kubernetes API responses
- **ViewModel Testing**: State management and business logic
- **Tree Building**: Algorithm correctness with various cluster configurations

### Integration Testing

- **End-to-End**: Full cluster connection and visualization flow
- **Performance**: Large cluster handling and memory usage
- **Error Scenarios**: Network failures, invalid configs, missing permissions

## Future Enhancements

### Architectural Improvements

1. **Plugin System**: Modular visualization types
2. **Caching Layer**: Persistent storage for cluster snapshots
3. **Real-time Updates**: WebSocket-based live cluster monitoring
4. **Multi-cluster**: Simultaneous visualization of multiple clusters

### Performance Optimizations

1. **Incremental Updates**: Only refresh changed resources
2. **Virtualization**: Handle very large clusters efficiently
3. **Background Refresh**: Automatic data updates without UI blocking
4. **Progressive Loading**: Stream data as it becomes available

### User Experience

1. **Custom Layouts**: Alternative visualization algorithms
2. **Filtering**: Show/hide specific resource types or namespaces
3. **Search**: Find specific resources quickly
4. **Bookmarks**: Save specific cluster views and configurations

## Conclusion

Clustermap's architecture prioritizes:

- **Maintainability**: Clean separation of concerns and testable components
- **Performance**: Efficient data structures and concurrent processing
- **User Experience**: Responsive UI with graceful error handling
- **Extensibility**: Modular design enabling future enhancements

The MVVM pattern combined with SwiftUI's reactive architecture provides a solid foundation for building a professional Kubernetes visualization tool that scales from small development clusters to large production environments.
