import Foundation

#if canImport(Supabase)
import Supabase
#endif

final class SupabaseManager {
    static let shared = SupabaseManager()

    private init() {}

    #if canImport(Supabase)
    private enum Constants {
        static let urlString = "https://dirgcwziayipwvwztjbb.supabase.co/rest/v1/"
        static let publishableKey = "sb_publishable_j7V-u1tMxcessnU4qQZe6g_x29a4l_Y"
    }

    private static let configuredURL: URL = {
        guard let url = URL(string: Constants.urlString) else {
            preconditionFailure("Invalid Supabase URL in SupabaseManager.")
        }
        return url
    }()

    let client = SupabaseClient(
        supabaseURL: configuredURL,
        supabaseKey: Constants.publishableKey
    )

    /// Connectivity smoke test for Supabase.
    /// Tries to fetch the first row from `family_members`.
    func testConnection() async {
        do {
            let rows: [[String: String]] = try await client
                .from("family_members")
                .select()
                .limit(1)
                .execute()
                .value

            if let firstRow = rows.first {
                print("Supabase connected. First family member row: \(firstRow)")
            } else {
                print("Supabase connected. `family_members` is reachable, but no rows found.")
            }
        } catch {
            print("Supabase connection test failed: \(error.localizedDescription)")
        }
    }
    #else
    func testConnection() async {
        print("Supabase SDK is unavailable in current build environment.")
    }
    #endif
}
