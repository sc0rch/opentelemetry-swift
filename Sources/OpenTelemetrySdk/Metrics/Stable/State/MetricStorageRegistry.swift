//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
// 

import Foundation
import OpenTelemetryApi

public class MetricStorageRegistry {
    private let queue = DispatchQueue(label: "com.example.MetricStorageRegistry.queue")
    private var registry = [MetricDescriptor : MetricStorage]()
    
    func getStorages() -> [MetricStorage] {
        return queue.sync {
            Array(registry.values)
        }
    }
    
    func register(newStorage : MetricStorage) -> MetricStorage {
        return queue.sync {
            let descriptor = newStorage.metricDescriptor
            
            // Проверяем, есть ли уже хранилище с таким дескриптором
            if let storage = registry[descriptor] {
                // Если есть, проверим совпадения по имени с другими дескрипторами (игнорируя регистр)
                for existingStorage in registry.values {
                    if existingStorage !== newStorage {
                        let existing = existingStorage.metricDescriptor
                        if existing.name.lowercased() == descriptor.name.lowercased(), existing != descriptor {
                            // TODO: Логгирование предупреждения о конфликте имен
                            break
                        }
                    }
                }
                return storage
            } else {
                // Если хранилища ещё нет, добавим новое
                registry[descriptor] = newStorage
                return newStorage
            }
        }
    }
}
