//
//  HashUtility.swift
//  Sorty
//
//  Centralized hashing utilities
//

import Foundation
import CryptoKit

public enum HashUtility {
    /// Compute SHA-256 hash for a file at the given URL using streaming to avoid memory issues
    public static func computeSHA256(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        
        defer {
            try? handle.close()
        }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB buffer
        
        while true {
            if Task.isCancelled {
                return nil
            }

            do {
                guard let data = try handle.read(upToCount: bufferSize), !data.isEmpty else {
                    break
                }
                hasher.update(data: data)
            } catch {
                return nil
            }
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
