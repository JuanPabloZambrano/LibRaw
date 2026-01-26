#!/usr/bin/env swift

import Foundation

// MARK: - Configuration

let SCRIPT_DIR = URL(fileURLWithPath: #file).deletingLastPathComponent()
let COLORDATA_PATH = SCRIPT_DIR.appendingPathComponent("../src/tables/colordata.cpp")
let CAMERALIST_PATH = SCRIPT_DIR.appendingPathComponent("../src/tables/cameralist.cpp")
let NORMALIZED_TESTS_PATH = URL(fileURLWithPath: "/Users/juanpablozambrano/Code/LibRaw/normalized_makes_model_testfiles.json")
let OUTPUT_PATH = SCRIPT_DIR.appendingPathComponent("libraw_camera_database.json")

// MARK: - Maker Mapping

let MAKER_MAP: [String: String] = [
    "Agfa": "AgfaPhoto", "Apple": "Apple", "Broadcom": "Broadcom",
    "RaspberryPi": "RaspberryPi", "Canon": "Canon", "Casio": "Casio",
    "Contax": "Contax", "DXO": "DXO", "Epson": "Epson",
    "Fujifilm": "FujiFilm", "GITUP": "GITUP", "GoPro": "GoPro",
    "Hasselblad": "Hasselblad", "HTC": "HTC", "Imacon": "Imacon",
    "Kodak": "Kodak", "Leaf": "Leaf", "Leica": "Leica",
    "Mamiya": "Mamiya", "Minolta": "Minolta", "Motorola": "Motorola",
    "Nikon": "Nikon", "Olympus": "Olympus", "OmDigital": "OmDigital",
    "Pentax": "Pentax", "Panasonic": "Panasonic", "PhaseOne": "PhaseOne",
    "Photron": "Photron", "Polaroid": "Polaroid", "RED": "RED",
    "Ricoh": "Ricoh", "Samsung": "Samsung", "Sigma": "Sigma",
    "Sony": "Sony", "YI": "Yi", "CINE": "CINE",
]

// Build flags for conditional cameras
let BUILD_FLAGS: [String: String] = [
    "USE_GPRSDK": "GoPro .GPR file support",
    "USE_X3FTOOLS": "Sigma X3F native support",
    "USE_6BY9RPI": "Raspberry Pi HQ Camera support",
]

// MARK: - Minimal Aliases (only for special cases that don't auto-match)
// Most aliases eliminated - normalized test file names match LibRaw directly!

let NAME_ALIASES: [String: [String]] = [
    // Sony M-series naming (M2 = II, M3 = III, etc.)
    "Sony DSC-RX0 II": ["Sony DSC-RX0M2"],
    "Sony DSC-RX100 II": ["Sony DSC-RX100M2"],
    "Sony DSC-RX100 III": ["Sony DSC-RX100M3"],
    "Sony DSC-RX100 IV": ["Sony DSC-RX100M4"],
    "Sony DSC-RX100 V": ["Sony DSC-RX100M5"],
    "Sony DSC-RX100 VII": ["Sony DSC-RX100M7", "Sony DSC-RX100M7A"],
    "Sony DSC-RX10 II": ["Sony DSC-RX10M2"],
    "Sony DSC-RX10 III": ["Sony DSC-RX10M3"],
    "Sony ILCE-6400": ["Sony ILCE-6400A"],

    // Nikon underscore naming (EXIF uses underscore, not space)
    "Nikon Z 6 II": ["Nikon Z 6_2"],
    "Nikon Z 7 II": ["Nikon Z 7_2"],
    "Nikon Z50 II": ["Nikon Z50_2"],
    "Nikon Z5 II": ["Nikon Z5_2"],
    "Nikon Z6III": ["Nikon Z6_3"],

    "Pentax K-3 Mark II": ["Pentax K-3 II"]
]

// MARK: - Data Models

struct TestFileEntry: Codable {
    let filename: String
    let normalized_make: String
    let normalized_model: String
    let is_dng: Bool
}

struct CameraEntry: Codable {
    let canonicalName: String
    let manufacturer: String
    let model: String
    let aliases: [String]
    let supportType: String  // "colordata", "cameralist", "conditional"
    let buildFlag: String?
    let hasTestFile: Bool
    let testFileNames: [String]
}

struct CameraDatabase: Codable {
    let generatedAt: String
    let totalCameras: Int
    let withTestFiles: Int
    let withoutTestFiles: Int
    let cameras: [CameraEntry]
}

// MARK: - Extraction Functions

func extractFromColordata() -> [(maker: String, model: String)] {
    guard let content = try? String(contentsOf: COLORDATA_PATH, encoding: .utf8) else {
        print("Error: Could not read colordata.cpp")
        return []
    }

    var cameras: [(maker: String, model: String)] = []
    let pattern = #"\{\s*LIBRAW_CAMERAMAKER_(\w+)\s*,\s*"([^"]+)""#

    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return []
    }

    let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
    var seen = Set<String>()

    for match in matches {
        if let makerRange = Range(match.range(at: 1), in: content),
           let modelRange = Range(match.range(at: 2), in: content) {
            let makerKey = String(content[makerRange])
            let model = String(content[modelRange])
            let manufacturer = MAKER_MAP[makerKey] ?? makerKey
            let fullName = "\(manufacturer) \(model)"

            if !seen.contains(fullName) {
                seen.insert(fullName)
                cameras.append((maker: manufacturer, model: model))
            }
        }
    }

    return cameras
}

func extractFromCameralist() -> (unconditional: [String], conditional: [(name: String, flag: String)]) {
    guard let content = try? String(contentsOf: CAMERALIST_PATH, encoding: .utf8) else {
        print("Error: Could not read cameralist.cpp")
        return ([], [])
    }

    var unconditional: [String] = []
    var conditional: [(name: String, flag: String)] = []
    var currentCondition: String? = nil
    var inList = false

    for line in content.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("static_camera_list[]") {
            inList = true
            continue
        }

        if inList {
            if trimmed == "NULL" {
                break
            }

            if trimmed.hasPrefix("#ifdef") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                currentCondition = parts.count > 1 ? parts[1] : nil
            } else if trimmed.hasPrefix("#endif") {
                currentCondition = nil
            } else if trimmed.hasPrefix("#") {
                continue
            }

            if let match = trimmed.range(of: #"^\s*"([^"]+)""#, options: .regularExpression) {
                let quoted = trimmed[match]
                let name = String(quoted.dropFirst().dropLast())

                if let cond = currentCondition {
                    conditional.append((name: name, flag: cond))
                } else {
                    unconditional.append(name)
                }
            }
        }
    }

    return (unconditional, conditional)
}

func loadTestFiles() -> [TestFileEntry] {
    guard let data = try? Data(contentsOf: NORMALIZED_TESTS_PATH),
          let files = try? JSONDecoder().decode([TestFileEntry].self, from: data) else {
        print("Error: Could not load normalized test files")
        return []
    }
    // Filter out DNGs - they don't need LibRaw camera-specific support
    return files.filter { !$0.is_dng }
}

// MARK: - Compound Model Expansion
// Handles entries like "DC-G90 / G95 / G91 / G99"

func expandCompoundModel(manufacturer: String, model: String) -> (primaryModel: String, variants: [String]) {
    guard model.contains(" / ") else {
        return (model, [])
    }

    let parts = model.components(separatedBy: " / ")
    guard parts.count > 1 else {
        return (model, [])
    }

    let primary = parts[0].trimmingCharacters(in: .whitespaces)
    var prefix = ""
    if let dashIndex = primary.lastIndex(of: "-") {
        let prefixEnd = primary.index(after: dashIndex)
        prefix = String(primary[..<prefixEnd])
    }

    var variants: [String] = []
    variants.append("\(manufacturer) \(model)") // Full compound name

    for i in 1..<parts.count {
        let part = parts[i].trimmingCharacters(in: .whitespaces)
        let expandedModel: String
        if part.contains("-") || part.hasPrefix(prefix) {
            expandedModel = part
        } else {
            expandedModel = "\(prefix)\(part)"
        }
        variants.append("\(manufacturer) \(expandedModel)")
    }

    return (primary, variants)
}

// MARK: - Normalization

func normalize(_ name: String) -> String {
    var norm = name.lowercased().trimmingCharacters(in: .whitespaces)
    norm = norm.replacingOccurrences(of: "-", with: " ")
    norm = norm.replacingOccurrences(of: "_", with: " ")
    norm = norm.replacingOccurrences(of: "/", with: " ")
    norm = norm.replacingOccurrences(of: ",", with: " ")

    if let regex = try? NSRegularExpression(pattern: "\\s*\\([^)]*\\)", options: []) {
        norm = regex.stringByReplacingMatches(in: norm, options: [], range: NSRange(norm.startIndex..., in: norm), withTemplate: "")
    }

    norm = norm.replacingOccurrences(of: "markiv", with: " mark iv")
    norm = norm.replacingOccurrences(of: "markiii", with: " mark iii")
    norm = norm.replacingOccurrences(of: "markii", with: " mark ii")

    if let regex = try? NSRegularExpression(pattern: "([a-z0-9])m2\\b", options: []) {
        norm = regex.stringByReplacingMatches(in: norm, options: [], range: NSRange(norm.startIndex..., in: norm), withTemplate: "$1 mark ii")
    }

    norm = norm.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    return norm
}

func testFileMatches(_ testFile: TestFileEntry, canonical: String, aliases: [String]) -> Bool {
    let testFullName = "\(testFile.normalized_make) \(testFile.normalized_model)"
    let testNorm = normalize(testFullName)
    let canonNorm = normalize(canonical)

    // Direct match
    if testNorm == canonNorm {
        return true
    }

    // Check aliases
    for alias in aliases {
        if testNorm == normalize(alias) {
            return true
        }
    }

    return false
}

// MARK: - Main

func main() {
    print("Building LibRaw Camera Database (Simplified V2)...")
    print("")

    // Extract from colordata (cameras with color matrices)
    print("Reading colordata.cpp...")
    let colordataCameras = extractFromColordata()
    print("  Found \(colordataCameras.count) cameras with color matrices")

    // Extract from cameralist
    print("Reading cameralist.cpp...")
    let (cameralistUnconditional, cameralistConditional) = extractFromCameralist()
    print("  Found \(cameralistUnconditional.count) unconditional cameras")
    print("  Found \(cameralistConditional.count) conditional cameras")

    // Load test files (auto-filtered DNGs)
    print("Reading normalized test files...")
    let testFiles = loadTestFiles()
    print("  Found \(testFiles.count) native RAW test files (DNGs excluded)")
    print("")

    // Build the database
    var cameras: [CameraEntry] = []
    var colordataNames = Set<String>()
    var colordataNormalized = Set<String>()

    // Process colordata cameras first (these have colordata support)
    for cam in colordataCameras {
        let (primaryModel, compoundVariants) = expandCompoundModel(manufacturer: cam.maker, model: cam.model)
        let canonicalName = "\(cam.maker) \(primaryModel)"

        colordataNames.insert(canonicalName.lowercased())
        colordataNormalized.insert(normalize(canonicalName))
        colordataNormalized.insert(normalize(primaryModel))

        for variant in compoundVariants {
            colordataNormalized.insert(normalize(variant))
        }

        var aliases = NAME_ALIASES[canonicalName] ?? []
        aliases.append(contentsOf: compoundVariants)

        // Check for conditional build flags
        var supportType = "colordata"
        var buildFlag: String? = nil

        if cam.maker == "GoPro" {
            supportType = "conditional"
            buildFlag = "USE_GPRSDK"
        } else if cam.maker == "Sigma" && (cam.model.contains("SD") || cam.model.contains("DP")) &&
                  !cam.model.lowercased().contains("quattro") {
            supportType = "conditional"
            buildFlag = "USE_X3FTOOLS"
        } else if cam.maker == "RaspberryPi" {
            supportType = "conditional"
            buildFlag = "USE_6BY9RPI"
        } else if cam.maker == "Polaroid" && cam.model == "x530" {
            supportType = "conditional"
            buildFlag = "USE_X3FTOOLS"
        }

        // Find matching test files
        var matchedNames: [String] = []
        for testFile in testFiles {
            if testFileMatches(testFile, canonical: canonicalName, aliases: aliases) {
                let testName = "\(testFile.normalized_make) \(testFile.normalized_model)"
                if !matchedNames.contains(testName) {
                    matchedNames.append(testName)
                }
            }
        }

        cameras.append(CameraEntry(
            canonicalName: canonicalName,
            manufacturer: cam.maker,
            model: primaryModel,
            aliases: aliases,
            supportType: supportType,
            buildFlag: buildFlag,
            hasTestFile: !matchedNames.isEmpty,
            testFileNames: matchedNames
        ))
    }

    // Process cameralist cameras that are not in colordata (cameralist-only)
    for camName in cameralistUnconditional {
        let parts = camName.components(separatedBy: " ")
        let manufacturer = parts.first ?? "Unknown"
        let rawModel = parts.dropFirst().joined(separator: " ")

        let (primaryModel, compoundVariants) = expandCompoundModel(manufacturer: manufacturer, model: rawModel)
        let canonicalName = "\(manufacturer) \(primaryModel)"

        let camNorm = normalize(canonicalName)
        if colordataNames.contains(canonicalName.lowercased()) || colordataNormalized.contains(camNorm) {
            continue
        }
        if colordataNormalized.contains(normalize(primaryModel)) {
            continue
        }

        var aliases = NAME_ALIASES[canonicalName] ?? []
        aliases.append(contentsOf: compoundVariants)
        if let originalAliases = NAME_ALIASES[camName], canonicalName != camName {
            aliases.append(contentsOf: originalAliases)
        }

        var matchedNames: [String] = []
        for testFile in testFiles {
            if testFileMatches(testFile, canonical: canonicalName, aliases: aliases) {
                let testName = "\(testFile.normalized_make) \(testFile.normalized_model)"
                if !matchedNames.contains(testName) {
                    matchedNames.append(testName)
                }
            }
        }

        cameras.append(CameraEntry(
            canonicalName: canonicalName,
            manufacturer: manufacturer,
            model: primaryModel.isEmpty ? canonicalName : primaryModel,
            aliases: aliases,
            supportType: "cameralist",
            buildFlag: nil,
            hasTestFile: !matchedNames.isEmpty,
            testFileNames: matchedNames
        ))
    }

    // Process conditional cameras from cameralist
    for (camName, flag) in cameralistConditional {
        let parts = camName.components(separatedBy: " ")
        let manufacturer = parts.first ?? "Unknown"
        let rawModel = parts.dropFirst().joined(separator: " ")

        let (primaryModel, compoundVariants) = expandCompoundModel(manufacturer: manufacturer, model: rawModel)
        let canonicalName = "\(manufacturer) \(primaryModel)"

        let camNorm = normalize(canonicalName)
        if colordataNames.contains(canonicalName.lowercased()) || colordataNormalized.contains(camNorm) {
            continue
        }

        var aliases = NAME_ALIASES[canonicalName] ?? []
        aliases.append(contentsOf: compoundVariants)
        if let originalAliases = NAME_ALIASES[camName], canonicalName != camName {
            aliases.append(contentsOf: originalAliases)
        }

        var matchedNames: [String] = []
        for testFile in testFiles {
            if testFileMatches(testFile, canonical: canonicalName, aliases: aliases) {
                let testName = "\(testFile.normalized_make) \(testFile.normalized_model)"
                if !matchedNames.contains(testName) {
                    matchedNames.append(testName)
                }
            }
        }

        cameras.append(CameraEntry(
            canonicalName: canonicalName,
            manufacturer: manufacturer,
            model: primaryModel.isEmpty ? canonicalName : primaryModel,
            aliases: aliases,
            supportType: "conditional",
            buildFlag: flag,
            hasTestFile: !matchedNames.isEmpty,
            testFileNames: matchedNames
        ))
    }

    // Sort by manufacturer then model
    cameras.sort { ($0.manufacturer, $0.model) < ($1.manufacturer, $1.model) }

    // Calculate stats
    let withTestFiles = cameras.filter { $0.hasTestFile }.count
    let withoutTestFiles = cameras.count - withTestFiles

    // Create database
    let dateFormatter = ISO8601DateFormatter()
    let database = CameraDatabase(
        generatedAt: dateFormatter.string(from: Date()),
        totalCameras: cameras.count,
        withTestFiles: withTestFiles,
        withoutTestFiles: withoutTestFiles,
        cameras: cameras
    )

    // Write to JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    if let jsonData = try? encoder.encode(database) {
        try? jsonData.write(to: OUTPUT_PATH)
        print("Database written to: libraw_camera_database.json")
    }

    // Print summary
    print("")
    print(String(repeating: "=", count: 60))
    print("SUMMARY")
    print(String(repeating: "=", count: 60))
    print("Total cameras in database: \(cameras.count)")
    print("  With test files: \(withTestFiles)")
    print("  Without test files: \(withoutTestFiles)")
    print("")
    print("By support type:")
    print("  Colordata (color matrix): \(cameras.filter { $0.supportType == "colordata" }.count)")
    print("  Cameralist (DNG-only): \(cameras.filter { $0.supportType == "cameralist" }.count)")
    print("  Conditional (SDK): \(cameras.filter { $0.supportType == "conditional" }.count)")
    print("")
    print("🎉 Simplification achieved:")
    print("  - DNGs auto-filtered from test files")
    print("  - Manual aliases mostly eliminated")
    print("  - Direct normalized name matching")
}

main()
