import Foundation
import SwiftData

@MainActor
enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeSchema() -> Schema {
        Schema([
            BreakEntity.self,
            WorkConfigurationEntity.self,
            DayOverrideEntity.self,
            NotificationRuleEntity.self,
            AppPreferenceEntity.self
        ])
    }
}
