import CoreLocation
import Foundation
import MapKit

/// 将稀疏锚点通过 MapKit Directions 贴路；失败段降级为直线。结果带内存/磁盘缓存。
actor RoadSnapRouteBuilder {
    static let shared = RoadSnapRouteBuilder()

    private var cache: [String: [CLLocationCoordinate2D]] = [:]
    private var inflight: [String: Task<[CLLocationCoordinate2D], Never>] = [:]
    private var activeDirectionsTasks = 0

    struct DirectionsBudget: Sendable {
        var remaining: Int

        mutating func consume(_ count: Int = 1) -> Bool {
            guard remaining >= count else { return false }
            remaining -= count
            return true
        }
    }

    /// 带全局 Directions 配额；配额不足时返回锚点折线。
    func roadCoordinates(
        for segment: LocationTrailSegment,
        budget: inout DirectionsBudget
    ) async -> [CLLocationCoordinate2D] {
        let cacheKey = "seg:\(segment.id.uuidString.lowercased())"
        if let cached = cache[cacheKey] { return cached }
        if let disk = Self.loadDiskCache(segmentId: segment.id) {
            cache[cacheKey] = disk
            return disk
        }

        let anchors = Self.anchors(from: segment.waypoints)
        guard anchors.count >= 2 else { return anchors }

        let pairsNeeded = anchors.count - 1
        if budget.remaining < pairsNeeded {
            return anchors
        }

        var budgetBox: DirectionsBudget? = budget
        let coords = await buildRoute(anchors: anchors, cacheKey: cacheKey, budget: &budgetBox)
        if let updated = budgetBox {
            budget = updated
        }
        if coords.count >= 2 {
            Self.saveDiskCache(segmentId: segment.id, coordinates: coords)
        }
        return coords
    }

    func roadCoordinates(for waypoints: [TrailWaypoint]) async -> [CLLocationCoordinate2D] {
        let anchors = Self.anchors(from: waypoints)
        guard anchors.count >= 2 else { return anchors }
        let cacheKey = Self.cacheKey(for: anchors)
        var noBudget: DirectionsBudget? = nil
        return await buildRoute(anchors: anchors, cacheKey: cacheKey, budget: &noBudget)
    }

    func clearCache() {
        cache.removeAll()
        inflight.removeAll()
    }

    private func buildRoute(
        anchors: [CLLocationCoordinate2D],
        cacheKey: String,
        budget: inout DirectionsBudget?
    ) async -> [CLLocationCoordinate2D] {
        if let cached = cache[cacheKey] { return cached }

        let result: [CLLocationCoordinate2D]
        if budget != nil {
            result = await buildPolyline(anchors: anchors, budget: &budget)
        } else {
            if let existing = inflight[cacheKey] {
                return await existing.value
            }
            let task = Task<[CLLocationCoordinate2D], Never> {
                var noBudget: DirectionsBudget? = nil
                return await RoadSnapRouteBuilder.shared.buildPolyline(anchors: anchors, budget: &noBudget)
            }
            inflight[cacheKey] = task
            result = await task.value
            inflight[cacheKey] = nil
        }

        cache[cacheKey] = result
        return result
    }

    private func buildPolyline(
        anchors: [CLLocationCoordinate2D],
        budget: inout DirectionsBudget?
    ) async -> [CLLocationCoordinate2D] {
        var path: [CLLocationCoordinate2D] = []
        for index in 0..<(anchors.count - 1) {
            let start = anchors[index]
            let end = anchors[index + 1]

            let segment: [CLLocationCoordinate2D]
            if var b = budget {
                if b.consume() {
                    budget = b
                    segment = await runDirections(from: start, to: end)
                } else {
                    segment = [start, end]
                }
            } else {
                segment = await runDirections(from: start, to: end)
            }

            if path.isEmpty {
                path.append(contentsOf: segment)
            } else if segment.count >= 2 {
                path.append(contentsOf: segment.dropFirst())
            } else {
                path.append(end)
            }
            if index < anchors.count - 2 {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
        return path
    }

    private func runDirections(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        while activeDirectionsTasks >= LocationRoadSnapPreferences.maxConcurrentDirections {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        activeDirectionsTasks += 1
        defer { activeDirectionsTasks -= 1 }
        return await Self.directions(from: from, to: to)
    }

    private static func directions(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        let distance = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
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

    nonisolated private static func anchors(from waypoints: [TrailWaypoint]) -> [CLLocationCoordinate2D] {
        waypoints.compactMap { waypoint in
            let coord = CLLocationCoordinate2D(latitude: waypoint.latitude, longitude: waypoint.longitude)
            guard Self.isValidForDirections(coord) else { return nil }
            return coord
        }
    }

    nonisolated private static func isValidForDirections(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && abs(coordinate.latitude) <= 90
            && abs(coordinate.longitude) <= 180
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

    private static func diskCacheURL(segmentId: UUID) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("road_snap", isDirectory: true)
            .appendingPathComponent("\(segmentId.uuidString.lowercased()).json")
    }

    private static func loadDiskCache(segmentId: UUID) -> [CLLocationCoordinate2D]? {
        guard let url = diskCacheURL(segmentId: segmentId),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Double]] else {
            return nil
        }
        let coords = raw.compactMap { dict -> CLLocationCoordinate2D? in
            guard let lat = dict["lat"], let lng = dict["lng"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return coords.filter { CLLocationCoordinate2DIsValid($0) }
    }

    private static func saveDiskCache(segmentId: UUID, coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2,
              let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = base.appendingPathComponent("road_snap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let url = diskCacheURL(segmentId: segmentId) else { return }
        let payload = coordinates.map { ["lat": $0.latitude, "lng": $0.longitude] }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
