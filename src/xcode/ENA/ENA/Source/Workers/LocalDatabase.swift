//
//  LocalDatabase.swift
//  ENA
//
//  Created by Bormeth, Marc on 16.05.20.
//

import Foundation
import FMDB
import ExposureNotification

protocol DataBaseWrapper {
    typealias FetchDBKeysCompletionHandler = (([(Data, String, Int?)]?, Error? ) -> Void)

    /// Store three-tuple that's fetched from the remote sever on local database
    func storePayload(payload: Data, day: String, hour: Int?)

    /// Get three-tuple that has been previously fetched from the remote sever from local database
    func fetchPayloads(with completion: @escaping FetchDBKeysCompletionHandler)

    /// Delete entries that aren't required any longer
    func clean(until date: Date)

}

final class LocalDatabase: DataBaseWrapper {
    private let db: FMDatabase

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-mm-dd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()

    init() {
        // swiftlint:disable:next force_try
        let url = try! FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("localdb.sqlite")

        db = FMDatabase(url: url)

        // Create tables
        let sqlStmt = """
            CREATE TABLE IF NOT EXISTS payloadStore (
                payload BLOB NOT NULL,
                day Date NOT NULL,
                hour INTEGER
            );
        """
        db.executeStatements(sqlStmt)
    }

    func storePayload(payload: Data, day: String, hour: Int?) {
        let insertStr = """
            INSERT INTO payloadStore(signedPayload, day, hour)
            VALUES(?, ?, ?);
        """

        if !db.isOpen {
            db.open()
        }

        // Transform day from String to Date to facilitate the clean up function
        let date = dateFormatter.date(from: day) ?? Date()

        do {
            try db.executeUpdate(insertStr, values: [payload, date, hour ?? NSNull()])
        } catch {
            logError(message: "Failed to store keys in local db: \(error.localizedDescription)")
        }
    }

    func fetchPayloads(with completion: @escaping FetchDBKeysCompletionHandler) {
        let query = "SELECT signedPayload, day, hour FROM payloadStore"
        var payloads = [(Data, String, Int?)]()
        let values = [Any]()

        func extractPayloads(result: FMResultSet) {
            while result.next() {
                // swiftlint:disable:next force_unwrapping
                let data = result.data(forColumn: "payload")!
                // swiftlint:disable:next force_unwrapping
                let day = dateFormatter.string(from: result.date(forColumn: "day")!)
                let hour = Int(result.int(forColumn: "hour"))
                payloads.append((data, day, hour))
            }
            completion(payloads, nil)
        }

        do {
            let result = try db.executeQuery(query, values: values)
            extractPayloads(result: result)
        } catch {
            completion(nil, error)
        }
    }

    func clean(until date: Date) {
        let threshold: Int32 = Int32(date.timeIntervalSince1970)
        let stmt = "DELETE FROM payloadStore WHERE day < \(threshold);"

        do {
            try db.executeUpdate(stmt, values: [Any]())
        } catch {
            // Don't notify, only a clean-up function
            logError(message: "Failed to clean-up db: \(error.localizedDescription)")
        }
    }

    deinit {
        db.close()
    }

}
