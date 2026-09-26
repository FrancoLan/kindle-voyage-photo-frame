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
            guard let item = items.first else { exit(4) }
            let result = item.addressRepresentations?.cityName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let result, !result.isEmpty else { exit(5) }
            print(result)
        } catch {
            FileHandle.standardError.write(Data("reverse geocoding failed: \(error.localizedDescription)\n".utf8))
            exit(6)
        }
    }
}
