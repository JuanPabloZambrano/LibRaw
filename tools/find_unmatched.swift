#!/usr/bin/env swift

import Foundation

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let dbPath = scriptDir.appendingPathComponent("libraw_camera_database.json")
let testFilesPath = URL(fileURLWithPath: "/Users/juanpablozambrano/Code/LibRaw/normalized_makes_model_testfiles.json")

// Manufacturers that only produce DNG files (phones, drones, etc.)
// These don't need LibRaw camera-specific support
let DNG_ONLY_MANUFACTURERS: Set<String> = [
    "Apple",        // iPhones
    "Google",       // Pixel phones
    "Huawei",       // Huawei phones
    "Samsung",      // Samsung phones (when not in LibRaw)
    "LG",           // LG phones
    "Motorola",     // Motorola phones
    "OnePlus",      // OnePlus phones
    "Xiaomi",       // Xiaomi phones
    "Realme",       // Realme phones
    "ASUS",         // ASUS phones
    "Microsoft",    // Lumia phones
    "DJI",          // DJI drones
    "Parrot",       // Parrot drones
    "Autel",        // Autel drones
    "FIMI",         // FIMI drones
    "Blackmagic",   // Blackmagic cinema cameras (DNG)
    "Arashi Vision", // Insta360
    "KanDao",       // KanDao 360 cameras
]

// Cameras that require special SDK build flags (conditional support)
// These won't match unless LibRaw is built with specific flags
let SDK_REQUIRED_MANUFACTURERS: Set<String> = [
    "GoPro",        // Requires USE_GPRSDK
    "RaspberryPi",  // Requires USE_6BY9RPI
]

struct TestFileEntry: Codable {
    let filename: String
    let normalized_make: String
    let normalized_model: String
    let is_dng: Bool
}

struct CamEntry: Codable {
    let testFileNames: [String]
}

struct DB: Codable {
    let cameras: [CamEntry]
}

guard let testFilesData = try? Data(contentsOf: testFilesPath),
      let testFiles = try? JSONDecoder().decode([TestFileEntry].self, from: testFilesData) else {
    print("Error loading normalized_makes_model_testfiles.json")
    exit(1)
}

guard let dbData = try? Data(contentsOf: dbPath),
      let db = try? JSONDecoder().decode(DB.self, from: dbData) else {
    print("Error loading libraw_camera_database.json")
    exit(1)
}

// Get all matched test file names
var matchedNames = Set<String>()
for cam in db.cameras {
    for name in cam.testFileNames {
        matchedNames.insert(name)
    }
}

// Find unmatched NATIVE RAW files
// Filter out: DNGs, DNG-only manufacturers, and SDK-required manufacturers
var unmatchedNative: [TestFileEntry] = []
let nativeRAWFiles = testFiles.filter { file in
    // Skip if it's a DNG file
    if file.is_dng { return false }

    // Skip if manufacturer only makes DNGs (phones, drones, etc.)
    if DNG_ONLY_MANUFACTURERS.contains(file.normalized_make) { return false }

    // Skip if manufacturer requires special SDK (GoPro, RaspberryPi)
    if SDK_REQUIRED_MANUFACTURERS.contains(file.normalized_make) { return false }

    return true
}

for testFile in nativeRAWFiles {
    let fullName = "\(testFile.normalized_make) \(testFile.normalized_model)"

    if !matchedNames.contains(fullName) && !matchedNames.contains(testFile.normalized_model) {
        unmatchedNative.append(testFile)
    }
}

print("Native RAW Test File Analysis")
print(String(repeating: "=", count: 60))
print("")

// Summary
let totalDNGs = testFiles.filter { $0.is_dng }.count
let totalDNGOnlyDevices = testFiles.filter { DNG_ONLY_MANUFACTURERS.contains($0.normalized_make) && !$0.is_dng }.count
let totalSDKRequired = testFiles.filter { SDK_REQUIRED_MANUFACTURERS.contains($0.normalized_make) && !$0.is_dng }.count
let totalIgnored = totalDNGs + totalDNGOnlyDevices + totalSDKRequired
let matched = nativeRAWFiles.count - unmatchedNative.count
print("Total test files: \(testFiles.count)")
print("  Ignored: \(totalIgnored)")
print("    - DNG files: \(totalDNGs)")
print("    - DNG-only devices: \(totalDNGOnlyDevices)")
print("    - SDK-required (GoPro, etc.): \(totalSDKRequired)")
print("  Camera RAW files to check: \(nativeRAWFiles.count)")
print("")
print("Camera RAW matching:")
print("  Matched to LibRaw:   \(matched)")
print("  Unmatched:           \(unmatchedNative.count)")
print("")

// Show unmatched cameras
if !unmatchedNative.isEmpty {
    print(String(repeating: "-", count: 60))
    print("UNMATCHED NATIVE RAWs:")
    print(String(repeating: "-", count: 60))
    print("These native RAW files aren't matching LibRaw cameras.")
    print("Possible reasons:")
    print("  - Camera not in LibRaw (unsupported)")
    print("  - Name mismatch (needs manual alias)")
    print("  - Regional variant (needs alias)")
    print("")

    var byMake: [String: [String]] = [:]
    for file in unmatchedNative {
        let make = file.normalized_make.isEmpty ? "Unknown" : file.normalized_make
        let fullName = file.normalized_make.isEmpty ? file.normalized_model : "\(file.normalized_make) \(file.normalized_model)"
        byMake[make, default: []].append(fullName)
    }

    for make in byMake.keys.sorted() {
        let cameras = Array(Set(byMake[make]!)).sorted()
        print("\(make) (\(cameras.count)):")
        for camera in cameras {
            print("  - \(camera)")
        }
    }
} else {
    print(String(repeating: "-", count: 60))
    print("✅ ALL NATIVE RAW FILES MATCHED!")
    print(String(repeating: "-", count: 60))
    print("All native RAW test files matched to LibRaw cameras.")
}
