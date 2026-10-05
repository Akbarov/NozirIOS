import MapKit
import SwiftUI
import NozirDesignSystem
import NozirLocation

extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

enum MapCamera {
    static func region(_ centre: Coordinate, metres: Double) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: CLLocationCoordinate2D(centre), latitudinalMeters: metres, longitudinalMeters: metres))
    }
}

/// The child's pin and the family's zones on Apple Maps. The zone the child is
/// in is drawn in the "good" colour, the rest in the brand colour; a stale pin
/// is faded. No user location, no key.
struct LocationMapView: View {
    let pin: Coordinate?
    let pinTitle: String
    let isStale: Bool
    let zones: [SafeZone]
    let currentZoneId: UUID?
    @Binding var position: MapCameraPosition
    var interactive = true

    var body: some View {
        Map(position: $position, interactionModes: interactive ? [.pan, .zoom] : []) {
            ForEach(zones) { zone in
                let colour = zone.id == currentZoneId ? NozirColor.goodContent : NozirColor.primary
                MapCircle(center: CLLocationCoordinate2D(zone.coordinate), radius: CLLocationDistance(zone.radiusMeters))
                    .foregroundStyle(colour.opacity(0.12))
                    .stroke(colour.opacity(0.55), lineWidth: 3)
            }
            if let pin {
                Annotation(pinTitle, coordinate: CLLocationCoordinate2D(pin)) {
                    Circle()
                        .fill(NozirColor.primary)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(radius: 2)
                        .opacity(isStale ? 0.45 : 1)
                }
            }
        }
    }
}
