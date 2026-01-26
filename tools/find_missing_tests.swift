#!/usr/bin/env swift

import Foundation

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let dbPath = scriptDir.appendingPathComponent("libraw_camera_database.json")

struct CamEntry: Codable {
    let canonicalName: String
    let manufacturer: String
    let model: String
    let aliases: [String]
    let supportType: String
    let buildFlag: String?
    let hasTestFile: Bool
    let testFileNames: [String]
}

struct DB: Codable {
    let generatedAt: String
    let totalCameras: Int
    let withTestFiles: Int
    let withoutTestFiles: Int
    let cameras: [CamEntry]
}

guard let dbData = try? Data(contentsOf: dbPath),
      let db = try? JSONDecoder().decode(DB.self, from: dbData) else {
    print("Error loading libraw_camera_database.json")
    exit(1)
}

// Filter cameras without test files
let missingTests = db.cameras.filter { !$0.hasTestFile }

print("LibRaw Cameras WITHOUT Test Files")
print(String(repeating: "=", count: 70))
print("")

// Summary
print("Total LibRaw cameras:     \(db.totalCameras)")
print("With test files:          \(db.withTestFiles)")
print("WITHOUT test files:       \(db.withoutTestFiles)")
print("")

// By support type
let colordataMissing = missingTests.filter { $0.supportType == "colordata" }
let cameralistMissing = missingTests.filter { $0.supportType == "cameralist" }
let conditionalMissing = missingTests.filter { $0.supportType == "conditional" }

print("By support type:")
print("  Colordata (color matrix):  \(colordataMissing.count)")
print("  Cameralist (DNG-only):     \(cameralistMissing.count)")
print("  Conditional (SDK):         \(conditionalMissing.count)")
print("")

// Group by manufacturer
var byMake: [String: [(name: String, type: String)]] = [:]
for cam in missingTests {
    byMake[cam.manufacturer, default: []].append((name: cam.canonicalName, type: cam.supportType))
}

print(String(repeating: "-", count: 70))
print("MISSING TEST FILES BY MANUFACTURER")
print(String(repeating: "-", count: 70))
print("")

// Sort manufacturers by count
let sortedMakers = byMake.keys.sorted { byMake[$0]!.count > byMake[$1]!.count }

for maker in sortedMakers {
    let cameras = byMake[maker]!

    // Count by type
    let colordataCount = cameras.filter { $0.type == "colordata" }.count
    let cameralistCount = cameras.filter { $0.type == "cameralist" }.count
    let conditionalCount = cameras.filter { $0.type == "conditional" }.count

    print("\(maker) (\(cameras.count) total):")
    if colordataCount > 0 { print("  [Colordata: \(colordataCount)]") }
    if cameralistCount > 0 { print("  [Cameralist: \(cameralistCount)]") }
    if conditionalCount > 0 { print("  [Conditional: \(conditionalCount)]") }

    // Sort cameras by name within manufacturer
    for cam in cameras.sorted(by: { $0.name < $1.name }) {
        let typeMarker: String
        switch cam.type {
        case "colordata": typeMarker = " [colordata]"
        case "cameralist": typeMarker = " [cameralist]"
        case "conditional": typeMarker = " [SDK]"
        default: typeMarker = ""
        }
        print("  - \(cam.name)\(typeMarker)")
    }
    print("")
}

// Export to file option
print(String(repeating: "-", count: 70))
print("Export detailed list to missing_tests.txt? (y/n): ", terminator: "")

if let response = readLine()?.lowercased(), response == "y" {
    var output = "LibRaw Cameras Without Test Files\n"
    output += String(repeating: "=", count: 70) + "\n\n"
    output += "Generated: \(db.generatedAt)\n\n"
    output += "Total: \(db.withoutTestFiles) cameras\n"
    output += "  Colordata: \(colordataMissing.count)\n"
    output += "  Cameralist: \(cameralistMissing.count)\n"
    output += "  Conditional: \(conditionalMissing.count)\n\n"

    for maker in sortedMakers {
        let cameras = byMake[maker]!
        output += "\(maker) (\(cameras.count)):\n"
        for cam in cameras.sorted(by: { $0.name < $1.name }) {
            let typeMarker: String
            switch cam.type {
            case "colordata": typeMarker = " [colordata]"
            case "cameralist": typeMarker = " [cameralist]"
            case "conditional": typeMarker = " [Requires SDK]"
            default: typeMarker = ""
            }
            output += "  - \(cam.name)\(typeMarker)\n"
        }
        output += "\n"
    }

    let outputPath = scriptDir.appendingPathComponent("missing_tests.txt")
    try? output.write(to: outputPath, atomically: true, encoding: .utf8)
    print("Exported to missing_tests.txt")
}
