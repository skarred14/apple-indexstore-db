//===--- IndexStoreDB.swift -----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_implementationOnly
import CIndexStoreDB

// For `strdup`
#if canImport(Glibc)
import Glibc
#elseif os(Windows)
import CRT
#else
import Darwin.POSIX
#endif

import Foundation

/// IndexStoreDB index.
public final class IndexStoreDB {

  let delegate: IndexDelegate?
  let impl: UnsafeMutableRawPointer // indexstoredb_index_t

  /// Create or open an IndexStoreDB at the givin `databasePath`.
  ///
  /// * Parameters:
  ///   * storePath: Path to the index store.
  ///   * databasePath: Path to the index database (or where it will be created).
  ///   * library: The index store library to use.
  ///   * delegate: The delegate to receive index events.
  ///   * wait: If `true`, wait for the database to be populated from the
  ///     (current) contents of the index store at `storePath` before returning.
  ///   * readonly: If `true`, read an existing database, but do not create or modify.
  ///   * listenToUnitEvents: Only `true` is supported outside unit tests. Setting to `false`
  ///     disables reading or updating from the index store unless `pollForUnitChangesAndWait()`
  ///     is called.
  public init(
    storePath: String,
    databasePath: String,
    library: IndexStoreLibrary?,
    delegate: IndexDelegate? = nil,
    useExplicitOutputUnits: Bool = false,
    waitUntilDoneInitializing wait: Bool = false,
    readonly: Bool = false,
    listenToUnitEvents: Bool = true
  ) throws {
    self.delegate = delegate

    let libProviderFunc: indexstore_library_provider_t = { (cpath: UnsafePointer<Int8>) -> indexstoredb_indexstore_library_t? in
      return library?.library
    }

    let delegateFunc = { [weak delegate] (event: indexstoredb_delegate_event_t) -> () in
      delegate?.handleEvent(event)
    }

    var error: indexstoredb_error_t? = nil
    guard let index = indexstoredb_index_create(storePath, databasePath, libProviderFunc, delegateFunc, useExplicitOutputUnits, wait, readonly, listenToUnitEvents, &error) else {
      defer { indexstoredb_error_dispose(error) }
      throw IndexStoreDBError.create(error?.description ?? "unknown")
    }

    impl = index
  }

  /// Wraps an existing `indexstoredb_index_t`.
  ///
  /// * Parameters:
  ///   * cIndex: An existing `indexstoredb_index_t` object.
  ///   * delegate: The delegate to receive index events.
  public init(
    cIndex: UnsafeMutableRawPointer/*indexstoredb_index_t*/,
    delegate: IndexDelegate? = nil)
  {
    self.delegate = delegate
    self.impl = cIndex

    indexstoredb_index_add_delegate(cIndex) { [weak delegate] event in
      delegate?.handleEvent(event)
    }
  }

  deinit {
    indexstoredb_release(impl)
  }

  /// *For Testing* Poll for any changes to units and wait until they have been registered.
  public func pollForUnitChangesAndWait() {
    indexstoredb_index_poll_for_unit_changes_and_wait(impl)
  }

  /// Add output filepaths for the set of unit files that index data should be loaded from.
  /// Only has an effect if `useExplicitOutputUnits` was set to true at initialization.
  public func addUnitOutFilePaths(_ paths: [String], waitForProcessing: Bool) {
    let cPaths: [UnsafePointer<CChar>] = paths.map { UnsafePointer($0.withCString(strdup)!) }
    defer { for cPath in cPaths { UnsafeMutablePointer(mutating: cPath)?.deallocate() } }
    return indexstoredb_index_add_unit_out_file_paths(impl, cPaths, cPaths.count, waitForProcessing)
  }

  /// Remove output filepaths for the set of unit files that index data should be loaded from.
  /// Only has an effect if `useExplicitOutputUnits` was set to true at initialization.
  public func removeUnitOutFilePaths(_ paths: [String], waitForProcessing: Bool) {
    let cPaths: [UnsafePointer<CChar>] = paths.map { UnsafePointer($0.withCString(strdup)!) }
    defer { for cPath in cPaths { UnsafeMutablePointer(mutating: cPath)?.deallocate() } }
    return indexstoredb_index_remove_unit_out_file_paths(impl, cPaths, cPaths.count, waitForProcessing)
  }

  @discardableResult
  public func forEachSymbolOccurrence(byUSR usr: String, roles: SymbolRole, _ body: @escaping (SymbolOccurrence) -> Bool) -> Bool {
    return indexstoredb_index_symbol_occurrences_by_usr(impl, usr, roles.rawValue) { occur in
      return body(SymbolOccurrence(occur))
    }
  }

  public func occurrences(ofUSR usr: String, roles: SymbolRole) -> [SymbolOccurrence] {
    var result: [SymbolOccurrence] = []
    forEachSymbolOccurrence(byUSR: usr, roles: roles) { occur in
      result.append(occur)
      return true
    }
    return result
  }

  @discardableResult
  public func forEachRelatedSymbolOccurrence(byUSR usr: String, roles: SymbolRole, _ body: @escaping (SymbolOccurrence) -> Bool) -> Bool {
    return indexstoredb_index_related_symbol_occurrences_by_usr(impl, usr, roles.rawValue) { occur in
      return body(SymbolOccurrence(occur))
    }
  }

  public func occurrences(relatedToUSR usr: String, roles: SymbolRole) -> [SymbolOccurrence] {
    var result: [SymbolOccurrence] = []
    forEachRelatedSymbolOccurrence(byUSR: usr, roles: roles) { occur in
      result.append(occur)
      return true
    }
    return result
  }

  @discardableResult public func forEachCanonicalSymbolOccurrence(byName: String, body: @escaping (SymbolOccurrence) -> Bool) -> Bool {
    return indexstoredb_index_canonical_symbol_occurences_by_name(impl, byName) { occur in
      return body(SymbolOccurrence(occur))
    }
  }

  public func canonicalOccurrences(ofName name: String) -> [SymbolOccurrence] {
    var result: [SymbolOccurrence] = []
    forEachCanonicalSymbolOccurrence(byName: name) { occur in
      result.append(occur)
      return true
    }
    return result
  }

  @discardableResult public func forEachCanonicalSymbolOccurrence(
    containing pattern: String,
    anchorStart: Bool,
    anchorEnd: Bool,
    subsequence: Bool,
    ignoreCase: Bool,
    body: @escaping (SymbolOccurrence) -> Bool
  ) -> Bool {
    return indexstoredb_index_canonical_symbol_occurences_containing_pattern(
      impl,
      pattern,
      anchorStart,
      anchorEnd,
      subsequence,
      ignoreCase
    ) { occur in
      body(SymbolOccurrence(occur))
    }
  }

  public func canonicalOccurrences(
    containing pattern: String,
    anchorStart: Bool,
    anchorEnd: Bool,
    subsequence: Bool,
    ignoreCase: Bool
  ) -> [SymbolOccurrence] {
    var result: [SymbolOccurrence] = []
    forEachCanonicalSymbolOccurrence(
      containing: pattern,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      subsequence: subsequence,
      ignoreCase: ignoreCase)
    { occur in
      result.append(occur)
      return true
    }
    return result
  }

  @discardableResult
  public func forEachMainFileContainingFile(path: String, crossLanguage: Bool, body: @escaping (String) -> Bool) -> Bool {
    let fromSwift = path.hasSuffix(".swift")
    return indexstoredb_index_units_containing_file(impl, path) { unit in
      let mainFileStr = String(cString: indexstoredb_unit_info_main_file_path(unit))
      let toSwift = mainFileStr.hasSuffix(".swift")
      if !crossLanguage && fromSwift != toSwift {
        return true // continue
      }
      return body(mainFileStr)
    }
  }

  public func mainFilesContainingFile(path: String, crossLanguage: Bool = false) -> [String] {
    var result: [String] = []
    forEachMainFileContainingFile(path: path, crossLanguage: crossLanguage) { mainFile in
      result.append(mainFile)
      return true
    }
    return result
  }

  @discardableResult
  public func forEachUnitNameContainingFile(path: String, body: @escaping (String) -> Bool) -> Bool {
    return indexstoredb_index_units_containing_file(impl, path) { unit in
      let unitName = String(cString: indexstoredb_unit_info_unit_name(unit))
      return body(unitName)
    }
  }

  public func unitNamesContainingFile(path: String) -> [String] {
    var result: [String] = []
    forEachUnitNameContainingFile(path: path) { unitName in
      result.append(unitName)
      return true
    }
    return result
  }
    
  @discardableResult
  public func foreachFileIncludedByFile(path: String, body: @escaping (String) -> Bool) -> Bool {
    return indexstoredb_index_files_included_by_file(impl, path) { targetPath, line in
        let targetPathStr = String(cString: targetPath)
        return body(targetPathStr)
    }
  }
    
  public func filesIncludedByFile(path: String) -> [String] {
    var result: [String] = []
    foreachFileIncludedByFile(path: path) { targetPath in
        result.append(targetPath)
        return true
    }
    return result
  }
    
  @discardableResult
  public func foreachFileIncludingFile(path: String, body: @escaping (String) -> Bool) -> Bool {
    return indexstoredb_index_files_including_file(impl, path) { sourcePath, line in
        let sourcePathStr = String(cString: sourcePath)
        return body(sourcePathStr)
    }
  }
      
  public func filesIncludingFile(path: String) -> [String] {
    var result: [String] = []
    foreachFileIncludingFile(path: path) { targetPath in
        result.append(targetPath)
        return true
      }
      return result
    }

  /// A recorded header `#include` from a unit file.
  public struct UnitIncludeEntry: Equatable {
    /// The path where the `#include` was added.
    public let sourcePath: String
    /// The path that the `#include` resolved to.
    public let targetPath: String
    /// the line where the `#include` was added.
    public let line: Int

    public init(sourcePath: String, targetPath: String, line: Int) {
      self.sourcePath = sourcePath
      self.targetPath = targetPath
      self.line = line
    }
  }

  /// Iterates over recorded `#include`s of a unit.
  @discardableResult
  public func forEachIncludeOfUnit(unitName: String, body: @escaping (UnitIncludeEntry) -> Bool) -> Bool {
    return indexstoredb_index_includes_of_unit(impl, unitName) { sourcePath, targetPath, line in
      let sourcePathStr = String(cString: sourcePath)
      let targetPathStr = String(cString: targetPath)
      return body(UnitIncludeEntry(sourcePath: sourcePathStr, targetPath: targetPathStr, line: line))
    }
  }

  /// Returns the recorded `#include`s of a unit.
  public func includesOfUnit(unitName: String) -> [UnitIncludeEntry] {
    var result: [UnitIncludeEntry] = []
    forEachIncludeOfUnit(unitName: unitName) { entry in
      result.append(entry)
      return true
    }
    return result
  }

  /// Iterates over the name of every symbol in the index.
  ///
  /// - Parameter body: A closure to be called for each symbol. The closure should return true to
  /// continue iterating.
  @discardableResult
  public func forEachSymbolName(body: @escaping (String) -> Bool) -> Bool {
    return indexstoredb_index_symbol_names(impl) { name in
      body(String(cString: name))
    }
  }

  /// Returns an array with every symbol name in the index.
  public func allSymbolNames() -> [String] {
    var result: [String] = []
    forEachSymbolName { name in
      result.append(name)
      return true
    }
    return result
  }

  public func symbols(inFilePath path: String) -> [Symbol] {
    var result: [Symbol] = []
    forEachSymbol(inFilePath: path) { sym in
      result.append(sym)
      return true
    }
    return result
  }

  @discardableResult
  func forEachSymbol(inFilePath filePath: String, body: @escaping (Symbol) -> Bool) -> Bool {
    return indexstoredb_index_symbols_contained_in_file_path(impl, filePath) { symbol in
      return body(Symbol(symbol))
    }
  }
}

public protocol IndexStoreLibraryProvider {
  func library(forStorePath: String) -> IndexStoreLibrary?
}

public class IndexStoreLibrary {
  let library: UnsafeMutableRawPointer // indexstoredb_indexstore_library_t

  public init(dylibPath: String) throws {
    var error: indexstoredb_error_t? = nil
    guard let lib = indexstoredb_load_indexstore_library(dylibPath, &error) else {
      defer { indexstoredb_error_dispose(error) }
      throw IndexStoreDBError.loadIndexStore(error?.description ?? "unknown")
    }

    self.library = lib
  }

  deinit {
    indexstoredb_release(library)
  }
}
