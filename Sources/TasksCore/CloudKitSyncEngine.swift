import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

public actor CloudKitSyncManager {
    public static let containerIdentifier = "iCloud.org.robertcrandall.Tasks"
    public static let zoneName = "TasksZone"
    public static let recordType = "TaskItem"

    private let isCloudKitEnabled: Bool
    private var lastSyncStatus: String = "Local App Group active"

    public init(enableCloudKit: Bool = CloudKitSyncManager.hasCloudKitEntitlementInCurrentProcess()) {
        self.isCloudKitEnabled = enableCloudKit
        if enableCloudKit {
            self.lastSyncStatus = "iCloud (\(Self.containerIdentifier)) active"
        } else {
            self.lastSyncStatus = "Team 7492ZAHAJV · Shared App Group + iCloud ready"
        }
    }

    public func statusSummary() -> String {
        lastSyncStatus
    }

    /// Checks whether the running binary is a bundled app with an embedded CloudKit provisioning profile.
    public static func hasCloudKitEntitlementInCurrentProcess() -> Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return false
        }
        #if os(macOS)
        let profileURL = Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
        guard FileManager.default.fileExists(atPath: profileURL.path) else {
            return false
        }
        #endif
        return Bundle.main.bundleIdentifier != nil
    }

    public func pushTasks(_ tasks: [TaskItem]) async {
        guard isCloudKitEnabled, !tasks.isEmpty else { return }
        #if canImport(CloudKit)
        do {
            let container = CKContainer(identifier: Self.containerIdentifier)
            let db = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
            _ = try? await db.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

            let recordIDs = tasks.map { CKRecord.ID(recordName: $0.id, zoneID: zoneID) }
            let existingResults = (try? await db.records(for: recordIDs)) ?? [:]
            var recordsToSave: [CKRecord] = []

            for item in tasks {
                let recordID = CKRecord.ID(recordName: item.id, zoneID: zoneID)
                if let result = existingResults[recordID], case .success(let existingRecord) = result {
                    let remoteUpdated = (existingRecord["updatedAt"] as? Date) ?? .distantPast
                    guard item.updatedAt > remoteUpdated else { continue }
                    try Self.populateRecord(existingRecord, with: item)
                    recordsToSave.append(existingRecord)
                } else {
                    recordsToSave.append(try Self.encodeRecord(item, zoneID: zoneID))
                }
            }

            if !recordsToSave.isEmpty {
                _ = try await db.modifyRecords(saving: recordsToSave, deleting: [], savePolicy: .ifServerRecordUnchanged)
            }
            lastSyncStatus = "Synced \(recordsToSave.count) tasks to iCloud"
        } catch {
            lastSyncStatus = "Local App Group synced (iCloud: \(error.localizedDescription))"
        }
        #endif
    }

    public func pullRemoteTasks() async -> [TaskItem]? {
        guard isCloudKitEnabled else { return nil }
        #if canImport(CloudKit)
        do {
            let container = CKContainer(identifier: Self.containerIdentifier)
            let db = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
            var (matchResults, cursor) = try await db.records(matching: query, inZoneWith: zoneID)
            var fetched: [TaskItem] = []
            while true {
                for (_, result) in matchResults {
                    if case .success(let record) = result,
                       let item = Self.decodeRecord(record) {
                        fetched.append(item)
                    }
                }
                guard let nextCursor = cursor else { break }
                (matchResults, cursor) = try await db.records(continuingMatchFrom: nextCursor)
            }
            lastSyncStatus = "Synced with iCloud (\(fetched.count) records)"
            return fetched
        } catch {
            lastSyncStatus = "Local App Group synced"
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(CloudKit)
    public static func encodeRecord(_ item: TaskItem, zoneID: CKRecordZone.ID) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        try populateRecord(record, with: item)
        return record
    }

    public static func populateRecord(_ record: CKRecord, with item: TaskItem) throws {
        let data = try JSONEncoder.tasksEncoder.encode(item)
        record["payloadJSON"] = String(data: data, encoding: .utf8) as CKRecordValue?
        record["title"] = item.title as CKRecordValue
        record["context"] = item.context.rawValue as CKRecordValue
        record["effort"] = item.effort.rawValue as CKRecordValue
        record["status"] = item.status.rawValue as CKRecordValue
        record["updatedAt"] = item.updatedAt as CKRecordValue
        record["isDeleted"] = (item.isDeleted ? 1 : 0) as CKRecordValue
    }

    public static func decodeRecord(_ record: CKRecord) -> TaskItem? {
        guard let json = record["payloadJSON"] as? String,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder.tasksDecoder.decode(TaskItem.self, from: data)
    }
    #endif
}

extension JSONEncoder {
    public static var tasksEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var tasksDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
