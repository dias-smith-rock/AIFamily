import Foundation

#if canImport(Supabase)
import Supabase
#endif

protocol SupabaseClientProviding {
    #if canImport(Supabase)
    var client: SupabaseClient { get }
    #endif
}

struct SupabaseProvider: SupabaseClientProviding {
    #if canImport(Supabase)
    let client: SupabaseClient

    init() {
        client = SupabaseManager.shared.client
    }
    #else
    init() {}
    #endif
}
