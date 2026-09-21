import CoreLocation
import Foundation
import MapKit

@main
struct ReverseGeocode {
    static func main() async {
        guard
            CommandLine.arguments.count == 3,
            let latitude = Double(CommandLine.arguments[1]),
            let longitude = Double(CommandLine.arguments[2]),
            (-90.0...90.0).contains(latitude),
            (-180.0...180.0).contains(longitude)
        else {
            FileHandle.standardError.write(Data("usage: reverse-geocode LATITUDE LONGITUDE\n".utf8))
            exit(2)
        }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { exit(3) }
        request.preferredLocale = Locale(identifier: "en_AU")

        do {
            let items = try await request.mapItems
            guard let placemark = items.first?.placemark else { exit(4) }
            let candidates: [String] = [
                placemark.subLocality,
                placemark.locality,
                placemark.subAdministrativeArea,
                placemark.administrativeArea,
            ].compactMap { value in
                guard let value else { return nil }
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
            guard let result = candidates.first else { exit(5) }
            print(result)
        } catch {
            FileHandle.standardError.write(Data("reverse geocoding failed: \(error.localizedDescription)\n".utf8))
            exit(6)
        }
    }
}
