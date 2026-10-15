import Combine
import CoreLocation
import Foundation
import MapKit

/// 校车行程的本地预览：锚点先经 MapKit 贴路，头像再沿贴路结果前进。
/// 不改真实定位，也不上报。
@MainActor
final class SchoolBusTripSession: ObservableObject {
    @Published private(set) var memberId: UUID?
    @Published private(set) var displayName = ""
    @Published private(set) var avatarURL: URL?
    @Published private(set) var trail: [CLLocationCoordinate2D] = []
    @Published private(set) var head: CLLocationCoordinate2D?
    @Published private(set) var speedKmh = 0
    @Published private(set) var hasArrived = false
    @Published private(set) var isActive = false
    /// 贴路结果就绪后递增，地图据此把整段路放进视野。
    @Published private(set) var routeReadyToken = 0

    private var route: [CLLocationCoordinate2D] = []
    private var cumulativeMeters: [Double] = []
    private var progressMeters: Double = 0
    private var runTask: Task<Void, Never>?

    var speedLabel: String { "\(speedKmh) km/h" }

    func start(member: UserLocationState, from origin: CLLocationCoordinate2D) {
        stop()
        let anchors = Self.makeAnchors(from: origin)
        guard anchors.count >= 2 else { return }
        memberId = member.id
        displayName = member.displayName
        avatarURL = member.avatarURL
        head = origin
        trail = [origin]
        speedKmh = 0
        hasArrived = false
        isActive = true
        runTask = Task { [weak self] in
            let waypoints = anchors.map { TrailWaypoint(coordinate: $0, recordedAt: Date()) }
            let snapped = await RoadSnapRouteBuilder.shared.roadCoordinates(for: waypoints)
            guard let self, !Task.isCancelled, self.isActive else { return }
            let geometry = snapped.count >= 2 ? snapped : anchors
            self.route = geometry
            self.cumulativeMeters = Self.distances(along: geometry)
            self.progressMeters = 0
            self.trail = [geometry[0]]
            self.head = geometry[0]
            self.speedKmh = 28
            self.routeReadyToken += 1
            #if DEBUG
            print(
                "[SchoolBusSnap] anchors=\(anchors.count) snapped=\(geometry.count) "
                    + "road=\(geometry.count > anchors.count)"
            )
            #endif
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isActive = false
        memberId = nil
        displayName = ""
        avatarURL = nil
        trail = []
        head = nil
        route = []
        cumulativeMeters = []
        progressMeters = 0
        speedKmh = 0
        hasArrived = false
        if routeReadyToken != 0 {
            routeReadyToken = 0
        }
    }

    /// 把整段预览路线放进视野。
    func previewRegion() -> MKCoordinateRegion? {
        guard route.isEmpty == false else { return nil }
        var rect = MKMapRect.null
        for coordinate in route {
            let point = MKMapPoint(coordinate)
            let dot = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            rect = rect.union(dot)
        }
        let padded = rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.35)
        return MKCoordinateRegion(padded)
    }

    private func advance() {
        guard isActive, hasArrived == false, let total = cumulativeMeters.last, total > 0 else { return }
        let wave = sin(progressMeters / 90)
        let speed = max(0, 24 + 12 * wave)
        speedKmh = Int(speed.rounded())
        progressMeters = min(total, progressMeters + speed / 3.6)
        let sample = Self.point(on: route, cumulative: cumulativeMeters, meters: progressMeters)
        head = sample
        trail = Self.trail(on: route, cumulative: cumulativeMeters, meters: progressMeters, head: sample)
        if progressMeters >= total - 0.5 {
            speedKmh = 0
            hasArrived = true
            runTask?.cancel()
            runTask = nil
        }
    }

    /// 只给 MapKit 几个相距超过 80 米的锚点，贴路后再沿结果折线前进。
    private static func makeAnchors(from origin: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let legs: [(bearing: Double, meters: Double)] = [
            (40, 220),
            (95, 260),
            (15, 240),
            (130, 200)
        ]
        var points = [origin]
        var cursor = origin
        for leg in legs {
            cursor = offset(cursor, meters: leg.meters, bearingDegrees: leg.bearing)
            points.append(cursor)
        }
        return points
    }

    private static func distances(along points: [CLLocationCoordinate2D]) -> [Double] {
        var meters: [Double] = [0]
        guard points.count >= 2 else { return meters }
        for index in 1..<points.count {
            let from = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
            let to = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            meters.append(meters[index - 1] + from.distance(from: to))
        }
        return meters
    }

    private static func point(
        on route: [CLLocationCoordinate2D],
        cumulative: [Double],
        meters: Double
    ) -> CLLocationCoordinate2D {
        guard route.count >= 2 else { return route[0] }
        let clamped = min(max(0, meters), cumulative.last ?? 0)
        var index = 1
        while index < cumulative.count - 1, cumulative[index] < clamped {
            index += 1
        }
        let startMeters = cumulative[index - 1]
        let endMeters = cumulative[index]
        let span = max(endMeters - startMeters, 0.001)
        let t = (clamped - startMeters) / span
        let a = route[index - 1]
        let b = route[index]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    private static func trail(
        on route: [CLLocationCoordinate2D],
        cumulative: [Double],
        meters: Double,
        head: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        for index in route.indices where cumulative[index] <= meters {
            points.append(route[index])
        }
        if let last = points.last {
            let gap = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: head.latitude, longitude: head.longitude))
            if gap > 1 { points.append(head) }
        } else {
            points = [head]
        }
        return points
    }

    private static func offset(
        _ origin: CLLocationCoordinate2D,
        meters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earth = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let angular = meters / earth
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
