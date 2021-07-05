// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "IndexStoreDB",
  products: [
    .library(
      name: "IndexStoreDB",
      targets: ["IndexStoreDB"]),
    .library(
      name: "IndexStoreDB_CXX",
      targets: ["IndexStoreDB_Index"]),
    .library(
      name: "ISDBTestSupport",
      targets: ["ISDBTestSupport"]),
    .executable(
      name: "tibs",
      targets: ["tibs"])
  ],
  dependencies: [],
  targets: [

    // MARK: Swift interface

    .target(
      name: "IndexStoreDB",
      dependencies: ["IndexStoreDB_CIndexStoreDB"],
      exclude: ["CMakeLists.txt"]),

    .testTarget(
      name: "IndexStoreDBTests",
      dependencies: ["IndexStoreDB", "ISDBTestSupport"]),

    // MARK: Swift Test Infrastructure

    // The Test Index Build System (tibs) library.
    .target(
      name: "ISDBTibs",
      dependencies: []),

    .testTarget(
      name: "ISDBTibsTests",
      dependencies: ["ISDBTibs", "ISDBTestSupport"]),

    // Commandline tool for working with tibs projects.
    .target(
      name: "tibs",
      dependencies: ["ISDBTibs"]),

    // Test support library, built on top of tibs.
    .target(
      name: "ISDBTestSupport",
      dependencies: ["IndexStoreDB", "ISDBTibs", "tibs"],
      resources: [
        .copy("INPUTS")
      ],
      linkerSettings: [
        .linkedFramework("XCTest", .when(platforms: [.iOS, .macOS, .tvOS, .watchOS]))
      ]),

    // MARK: C++ interface

    // Primary C++ interface.
    .target(
      name: "IndexStoreDB_Index",
      dependencies: ["IndexStoreDB_Database"],
      path: "lib/Index",
      exclude: [
        "CMakeLists.txt",
        "indexstore_functions.def",
      ]),

    // C wrapper for IndexStoreDB_Index.
    .target(
      name: "IndexStoreDB_CIndexStoreDB",
      dependencies: ["IndexStoreDB_Index"],
      path: "lib/CIndexStoreDB",
      exclude: ["CMakeLists.txt"]),

    // The lmdb database layer.
    .target(
      name: "IndexStoreDB_Database",
      dependencies: ["IndexStoreDB_Core"],
      path: "lib/Database",
      exclude: [
        "CMakeLists.txt",
        "lmdb/LICENSE",
        "lmdb/COPYRIGHT",
      ],
      cSettings: [
        .define("MDB_USE_POSIX_MUTEX", to: "1",
                // Windows does not use POSIX mutex
                .when(platforms: [.linux, .macOS])),
        .define("MDB_USE_ROBUST", to: "0"),
      ]),

    // Core index types.
    .target(
      name: "IndexStoreDB_Core",
      dependencies: ["IndexStoreDB_Support"],
      path: "lib/Core",
      exclude: ["CMakeLists.txt"]),

    // Support code that is generally useful to the C++ implementation.
    .target(
      name: "IndexStoreDB_Support",
      dependencies: ["IndexStoreDB_LLVMSupport"],
      path: "lib/Support",
      exclude: ["CMakeLists.txt"]),

    // Copy of a subset of llvm's ADT and Support libraries.
    .target(
      name: "IndexStoreDB_LLVMSupport",
      dependencies: [],
      path: "lib/LLVMSupport",
      exclude: [
        "LICENSE.TXT",
        "CMakeLists.txt",
        // *.inc, *.def
        "include/llvm/Support/AArch64TargetParser.def",
        "include/llvm/Support/ARMTargetParser.def",
        "include/llvm/Support/X86TargetParser.def",
        "Support/Unix/Host.inc",
        "Support/Unix/Memory.inc",
        "Support/Unix/Mutex.inc",
        "Support/Unix/Path.inc",
        "Support/Unix/Process.inc",
        "Support/Unix/Program.inc",
        "Support/Unix/Signals.inc",
        "Support/Unix/Threading.inc",
        "Support/Unix/Watchdog.inc",
        "Support/Windows/Host.inc",
        "Support/Windows/Memory.inc",
        "Support/Windows/Mutex.inc",
        "Support/Windows/Path.inc",
        "Support/Windows/Process.inc",
        "Support/Windows/Program.inc",
        "Support/Windows/Signals.inc",
        "Support/Windows/Threading.inc",
        "Support/Windows/Watchdog.inc",
      ]),
  ],

  cxxLanguageStandard: .cxx11
)
