import CoreLocation
import Foundation

enum TaskCompletionLocationProvider {
    /// 单次读取当前位置；失败（含用户拒绝定位）时返回 `nil`，不阻塞打勾完成。
    static func currentSnapshot(completedBy: UUID) async -> TaskCompletionLocation? {
        guard let coordinate = await DeviceLocationFetcher.currentCoordinate() else {
            return nil
        }
        return TaskCompletionLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            completedAt: Date(),
            completedBy: completedBy
        )
    }
}
