import CoreLocation
import Foundation
import MapKit

/// 将稀疏锚点通过 MapKit Directions 贴路；失败段降级为直线。结果带内存缓存。
actor RoadSnapRouteBuilder {
    static let shared = RoadSnapRouteBuilder()

    private var cache: [String: [CLLocationCoordinate2D]] = [:]
    /// 避免对同一段并发重复请求。
    private var inflight: [String: Task<[CLLocationCoordinate2D], Never>] = [:]

    func roadCoordinates(for waypoints: [TrailWaypoint]) async -> [CLLocationCoordinate2D] {
        let anchors = waypoints.map(\.coordinate).filter(\.isValidForDirections)
        guard anchors.count >= 2 else { return anchors }

        let cacheKey = Self.cacheKey(for: anchors)
        if let cached = cache[cacheKey] { return cached }

        if let existing = inflight[cacheKey] {
            return await existing.value
        }

        let task = Task<[CLLocationCoordinate2D], Never> {
            await Self.buildRoute(anchors: anchors)
        }
        inflight[cacheKey] = task
        let result = await task.value
        inflight[cacheKey] = nil
        cache[cacheKey] = result
        return result
    }

    func clearCache() {
        cache.removeAll()
        inflight.removeAll()
    }

    private static func buildRoute(anchors: [CLLocationCoordinate2D]) async -> [CLLocationCoordinate2D] {
        var path: [CLLocationCoordinate2D] = []
        for index in 0..<(anchors.count - 1) {
            let start = anchors[index]
            let end = anchors[index + 1]
            let segment = await directions(from: start, to: end)
            if path.isEmpty {
                path.append(contentsOf: segment)
            } else if segment.count >= 2 {
                path.append(contentsOf: segment.dropFirst())
            } else {
                path.append(end)
            }
            // 轻微节流，降低 Directions 限流风险
            if index < anchors.count - 2 {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
        return path
    }

    private static func directions(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        let distance = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        // 极近点无需算路
        if distance < 25 {
            return [from, to]
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            if let polyline = response.routes.first?.polyline {
                let coords = Self.coordinates(from: polyline)
                if coords.count >= 2 { return coords }
            }
        } catch {
            #if DEBUG
            print("[RoadSnap] directions failed: \(error.localizedDescription)")
            #endif
        }
        return [from, to]
    }

    nonisolated private static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords.filter { CLLocationCoordinate2DIsValid($0) }
    }

    private static func cacheKey(for anchors: [CLLocationCoordinate2D]) -> String {
        anchors.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) }.joined(separator: "|")
    }
}

private extension CLLocationCoordinate2D {
    var isValidForDirections: Bool {
        CLLocationCoordinate2DIsValid(self)
            && abs(latitude) <= 90
            && abs(longitude) <= 180
    }
}
