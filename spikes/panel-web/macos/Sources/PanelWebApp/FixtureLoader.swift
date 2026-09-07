// Loads the untouched Phase 0 fixture JSON from generated SwiftPM resources.
// Exports: FixtureLoader and Fixture.
// Dependencies: Foundation, Bundle.module, and JSONValue.

import Foundation

struct Fixture {
    let name: String
    let definition: [String: JSONValue]
    let initialState: [String: JSONValue]
}

enum FixtureLoaderError: Error { case missingResource(String); case malformed(String) }

struct FixtureLoader {
    func load(named name: String) throws -> Fixture {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else { throw FixtureLoaderError.missingResource(name) }
        let data = try Data(contentsOf: url)
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = root.objectValue else { throw FixtureLoaderError.malformed(name) }
        if let spec = object["spec"] { return Fixture(name: name, definition: ["spec": spec], initialState: object["initialState"]?.objectValue ?? [:]) }
        guard let formSpec = object["formSpec"] else { throw FixtureLoaderError.malformed(name) }
        let defaults = object["defaults"]?.objectValue ?? [:]
        return Fixture(name: name, definition: ["formSpec": formSpec], initialState: ["form": .object(defaults)])
    }
}
