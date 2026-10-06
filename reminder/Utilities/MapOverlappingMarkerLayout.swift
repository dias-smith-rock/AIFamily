import CoreLocation
import Foundation
import SwiftUI

/// 多人当前位置过近时，把头像在屏幕上错开，避免 MapKit 叠成一个点。
enum MapOverlappingMarkerLayout {
    static let mergeRadiusMeters: CLLocationDistance = 40
    private static let spreadRadiusPoints: CGFloat = 28

    struct Slot: Equatable {
        let index: Int
        let count: Int

        var screenOffset: CGSize {
            guard count > 1 else { return .zero }
            let radius = spreadRadiusPoints + CGFloat(max(0, count - 2)) * 4
            let angle = (2 * Double.pi * Double(index) / Double(count)) - Double.pi
            return CGSize(
                width: radius * CGFloat(cos(angle)),
                height: radius * CGFloat(sin(angle))
            )
        }

        /// 给 MapKit 一个可区分的坐标，避免同点只渲染一个 Annotation。
        func mapCoordinate(from base: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
            guard count > 1 else { return base }
            let meters = 0.9
            let angle = (2 * Double.pi * Double(index) / Double(count)) - Double.pi
            let dLat = (meters * cos(angle)) / 111_320.0
            let longitudeScale = 111_320.0 * max(cos(base.latitude * .pi / 180.0), 0.01)
            let dLng = (meters * sin(angle)) / longitudeScale
            return CLLocationCoordinate2D(
                latitude: base.latitude + dLat,
                longitude: base.longitude + dLng
            )
        }
    }

    static func slots(
        points: [(id: UUID, coordinate: CLLocationCoordinate2D)]
    ) -> [UUID: Slot] {
        var remaining = points
        var result: [UUID: Slot] = [:]
        while let seed = remaining.first {
            remaining.removeFirst()
            var cluster = [seed]
            remaining.removeAll { other in
                let distance = CLLocation(
                    latitude: seed.coordinate.latitude,
                    longitude: seed.coordinate.longitude
                ).distance(
                    from: CLLocation(
                        latitude: other.coordinate.latitude,
                        longitude: other.coordinate.longitude
                    )
                )
                guard distance <= mergeRadiusMeters else { return false }
                cluster.append(other)
                return true
            }
            cluster.sort { $0.id.uuidString < $1.id.uuidString }
            for (index, item) in cluster.enumerated() {
                result[item.id] = Slot(index: index, count: cluster.count)
            }
        }
        return result
    }
}
