import CoreLocation
import Foundation

/// 将密采轨迹压成稀疏锚点（Douglas-Peucker + 转向保留 + 上限）。
enum TrailSimplifier {
    static let defaultToleranceMeters: CLLocationDistance = 40
    static let defaultMaxPoints = 40
    static let significantTurnDegrees: Double = 45

    static func simplify(
        _ points: [TrailWaypoint],
        toleranceMeters: CLLocationDistance = defaultToleranceMeters,
        maxPoints: Int = defaultMaxPoints
    ) -> [TrailWaypoint] {
        guard points.count > 2 else { return points }

        var kept = douglasPeucker(points, toleranceMeters: toleranceMeters)
        kept = retainSignificantTurns(in: points, keeping: kept)
        kept = sortedChronologically(kept)

        if kept.count > maxPoints {
            kept = downsampleEvenly(kept, maxPoints: maxPoints)
        }
        return kept
    }

    // MARK: - Douglas-Peucker

    private static func douglasPeucker(
        _ points: [TrailWaypoint],
        toleranceMeters: CLLocationDistance
    ) -> [TrailWaypoint] {
        guard points.count > 2 else { return points }

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        var keep = Set<Int>([0, points.count - 1])

        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var maxDistance: CLLocationDistance = 0
            var index = start
            for i in (start + 1)..<end {
                let d = perpendicularDistanceMeters(
                    point: points[i],
                    lineStart: points[start],
                    lineEnd: points[end]
                )
                if d > maxDistance {
                    maxDistance = d
                    index = i
                }
            }
            if maxDistance > toleranceMeters {
                keep.insert(index)
                stack.append((start, index))
                stack.append((index, end))
            }
        }

        return keep.sorted().map { points[$0] }
    }

    private static func perpendicularDistanceMeters(
        point: TrailWaypoint,
        lineStart: TrailWaypoint,
        lineEnd: TrailWaypoint
    ) -> CLLocationDistance {
        let a = CLLocation(latitude: lineStart.latitude, longitude: lineStart.longitude)
        let b = CLLocation(latitude: lineEnd.latitude, longitude: lineEnd.longitude)
        let p = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let ab = a.distance(from: b)
        guard ab > 1 else { return a.distance(from: p) }

        // 平面近似：用局部米制投影
        let lat0 = (lineStart.latitude + lineEnd.latitude + point.latitude) / 3
        let metersPerDegLat = 111_320.0
        let metersPerDegLng = 111_320.0 * cos(lat0 * .pi / 180)
        // 局部米制：A→P、A→B
        let apx = (point.longitude - lineStart.longitude) * metersPerDegLng
        let apy = (point.latitude - lineStart.latitude) * metersPerDegLat
        let bx = (lineEnd.longitude - lineStart.longitude) * metersPerDegLng
        let by = (lineEnd.latitude - lineStart.latitude) * metersPerDegLat
        let denom = bx * bx + by * by
        let t = denom > 0.0001 ? max(0, min(1, (apx * bx + apy * by) / denom)) : 0
        let projLng = lineStart.longitude + t * (lineEnd.longitude - lineStart.longitude)
        let projLat = lineStart.latitude + t * (lineEnd.latitude - lineStart.latitude)
        let proj = CLLocation(latitude: projLat, longitude: projLng)
        return p.distance(from: proj)
    }

    // MARK: - Turn retention

    private static func retainSignificantTurns(
        in original: [TrailWaypoint],
        keeping: [TrailWaypoint]
    ) -> [TrailWaypoint] {
        guard original.count >= 3 else { return keeping }
        var result = keeping
        var seen = Set(keeping.map { coordinateKey($0) })

        for i in 1..<(original.count - 1) {
            let turn = turnDegrees(previous: original[i - 1], current: original[i], next: original[i + 1])
            guard turn >= significantTurnDegrees else { continue }
            let key = coordinateKey(original[i])
            if seen.insert(key).inserted {
                result.append(original[i])
            }
        }
        return result
    }

    private static func turnDegrees(
        previous: TrailWaypoint,
        current: TrailWaypoint,
        next: TrailWaypoint
    ) -> Double {
        let bearing1 = bearingDegrees(from: previous, to: current)
        let bearing2 = bearingDegrees(from: current, to: next)
        var delta = abs(bearing2 - bearing1)
        if delta > 180 { delta = 360 - delta }
        return delta
    }

    private static func bearingDegrees(from: TrailWaypoint, to: TrailWaypoint) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    private static func sortedChronologically(_ points: [TrailWaypoint]) -> [TrailWaypoint] {
        points.sorted { lhs, rhs in
            let l = lhs.recordedAt ?? .distantPast
            let r = rhs.recordedAt ?? .distantPast
            if l != r { return l < r }
            return lhs.latitude < rhs.latitude
        }
    }

    private static func downsampleEvenly(_ points: [TrailWaypoint], maxPoints: Int) -> [TrailWaypoint] {
        guard points.count > maxPoints, maxPoints >= 2 else { return points }
        var result: [TrailWaypoint] = [points[0]]
        let inner = maxPoints - 2
        for i in 1...inner {
            let index = Int(round(Double(i) * Double(points.count - 1) / Double(maxPoints - 1)))
            let clamped = min(points.count - 1, max(0, index))
            if result.last?.coordinate.latitude != points[clamped].latitude
                || result.last?.coordinate.longitude != points[clamped].longitude {
                result.append(points[clamped])
            }
        }
        let last = points[points.count - 1]
        if result.last?.coordinate.latitude != last.latitude
            || result.last?.coordinate.longitude != last.longitude {
            result.append(last)
        }
        return result
    }

    private static func coordinateKey(_ point: TrailWaypoint) -> String {
        String(format: "%.5f,%.5f", point.latitude, point.longitude)
    }
}
