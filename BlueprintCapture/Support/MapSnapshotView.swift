import SwiftUI
import MapKit

struct MapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        if #available(iOS 17.0, *) {
            Map(position: .constant(.region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))))
                .allowsHitTesting(false)
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: "map")
                    .foregroundStyle(.secondary)
            }
        }
    }
}


