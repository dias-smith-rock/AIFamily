import CoreLocation
import Foundation
import MapKit

/// 将稀疏锚点通过 MapKit Directions 贴路；失败段降级为直线。结果带内存/磁盘缓存。
actor RoadSnapRouteBuilder {
    static let shared = RoadSnapRouteBuilder()

    private var cache: [String: [CLLocationCoordinate2D]] = [:]
    private var inflight: [String: Task<[CLLocationCoordinate2D], Never>] = [:]
    private var activeDirectionsTasks = 0

    func roadCoordinates(for segment: LocationTrailSegment) async -> [CLLocationCoordinate2D] {
        let cacheKey = "seg:\(segment.id.uuidString.lowercased())"
        let segmentLabel = segment.id.uuidString.prefix(8)
        let anchors = Self.anchors(from: segment.waypoints)
        guard anchors.count >= 2 else {
            Self.trace("segment id=\(segmentLabel) anchors=\(anchors.count) skip=need_two_points")
            return anchors
        }

        if let cached = cache[cacheKey], cached.count > anchors.count {
            Self.trace(
                "segment id=\(segmentLabel) cache=memory points=\(cached.count) "
                    + Self.geometryLabel(resultCount: cached.count, anchorCount: anchors.count)
            )
            return cached
        }
        cache[cacheKey] = nil

        if let disk = Self.loadDiskCache(segmentId: segment.id) {
            if disk.count > anchors.count {
                cache[cacheKey] = disk
                Self.trace(
                    "segment id=\(segmentLabel) cache=disk points=\(disk.count) "
                        + Self.geometryLabel(resultCount: disk.count, anchorCount: anchors.count)
                )
                return disk
            }
            Self.removeDiskCache(segmentId: segment.id)
            Self.trace(
                "segment id=\(segmentLabel) cache=disk rejected points=\(disk.count) "
                    + "anchors=\(anchors.count) geometry=anchors_only"
            )
        }

        let coords = await buildRoute(anchors: anchors, cacheKey: cacheKey)
        let geometry = Self.geometryLabel(resultCount: coords.count, anchorCount: anchors.count)
        let accepted = Self.isRoadFollowingRoute(coords, anchors: anchors)
        if accepted {
            Self.saveDiskCache(segmentId: segment.id, coordinates: coords)
        }
        Self.trace(
            "segment id=\(segmentLabel) anchors=\(anchors.count) resultPts=\(coords.count) "
                + "\(geometry) roadCheck=\(accepted ? "accept" : "reject") "
                + "disk=\(accepted ? "saved" : "skipped")"
        )
        return coords
    }

    func roadCoordinates(for waypoints: [TrailWaypoint]) async -> [CLLocationCoordinate2D] {
        let anchors = Self.anchors(from: waypoints)
        guard anchors.count >= 2 else { return anchors }
        return await buildRoute(anchors: anchors, cacheKey: Self.cacheKey(for: anchors))
    }

    func clearCache() {
        cache.removeAll()
        inflight.removeAll()
    }

    private func buildRoute(
        anchors: [CLLocationCoordinate2D],
        cacheKey: String
    ) async -> [CLLocationCoordinate2D] {
        if let cached = cache[cacheKey] { return cached }
        if let existing = inflight[cacheKey] {
            return await existing.value
        }

        let task = Task<[CLLocationCoordinate2D], Never> {
            await RoadSnapRouteBuilder.shared.buildPolyline(anchors: anchors)
        }
        inflight[cacheKey] = task
        let result = await task.value
        inflight[cacheKey] = nil

        if Self.isRoadFollowingRoute(result, anchors: anchors) {
            cache[cacheKey] = result
        }
        return result
    }

    private func buildPolyline(
        anchors: [CLLocationCoordinate2D]
    ) async -> [CLLocationCoordinate2D] {
        var path: [CLLocationCoordinate2D] = []
        var snappedPairs = 0
        var straightPairs = 0
        for index in 0..<(anchors.count - 1) {
            let start = anchors[index]
            let end = anchors[index + 1]
            let segment = await runDirections(from: start, to: end)
            if segment.count > 2 {
                snappedPairs += 1
            } else {
                straightPairs += 1
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
        Self.trace(
            "polyline anchors=\(anchors.count) snappedPairs=\(snappedPairs) "
                + "straightPairs=\(straightPairs) resultPts=\(path.count)"
        )
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

    @MainActor
    private static func directions(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        let distance = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        let pair = "\(Self.coord(from)) -> \(Self.coord(to)) dist=\(Int(distance))m"
        if distance < 25 {
            trace("pair \(pair) result=skip_under_25m")
            return [from, to]
        }

        let transports: [MKDirectionsTransportType] = [.automobile, .any]
        var notes: [String] = []
        for transport in transports {
            let request = MKDirections.Request()
            request.source = mapItem(for: from)
            request.destination = mapItem(for: to)
            request.transportType = transport
            request.requestsAlternateRoutes = false
            let name = transport == .automobile ? "automobile" : "any"

            do {
                let response = try await MKDirections(request: request).calculate()
                if let polyline = response.routes.first?.polyline {
                    let coords = coordinates(from: polyline)
                    if isRoadFollowingRoute(coords, anchors: [from, to]) {
                        trace("pair \(pair) \(name)=ok pts=\(coords.count) result=road")
                        return coords
                    }
                    notes.append("\(name)=rejected pts=\(coords.count)")
                } else {
                    notes.append("\(name)=empty_route")
                }
            } catch {
                notes.append("\(name)=error:\(error.localizedDescription)")
            }
        }
        trace("pair \(pair) \(notes.joined(separator: " ")) result=straight")
        return [from, to]
    }

    #if DEBUG
    private static func trace(_ message: String) {
        print("[RoadSnapTrace] \(message)")
    }
    #else
    private static func trace(_ message: String) {}
    #endif

    private static func coord(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    /// 结果点数没有多于锚点时，折线就是锚点之间的直线，即使超过 2 个点也不算贴路。
    private static func geometryLabel(resultCount: Int, anchorCount: Int) -> String {
        if anchorCount >= 2, resultCount > anchorCount {
            return "geometry=road_vertices"
        }
        return "geometry=anchors_only"
    }

    private static func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26.0, *) {
            return MKMapItem(location: location, address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }

    /// 真正沿路的折线会比两个锚点更密；长距离只剩起终点则视为失败，不写入缓存。
    private static func isRoadFollowingRoute(
        _ coords: [CLLocationCoordinate2D],
        anchors: [CLLocationCoordinate2D]
    ) -> Bool {
        guard coords.count >= 2, anchors.count >= 2 else { return false }
        if coords.count > anchors.count { return true }
        guard let start = anchors.first, let end = anchors.last else { return false }
        let distance = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        return distance < 80
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

    private static func removeDiskCache(segmentId: UUID) {
        guard let url = diskCacheURL(segmentId: segmentId) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
