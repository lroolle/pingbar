import Foundation

struct HistoryBuffer<T> {
    private var storage: [T]
    private let capacity: Int
    private var writeIndex = 0
    private var isFull = false

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    mutating func append(_ value: T) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[writeIndex] = value
        }
        writeIndex = (writeIndex + 1) % capacity
        if writeIndex == 0 && storage.count == capacity {
            isFull = true
        }
    }

    var values: [T] {
        if storage.count < capacity {
            return storage
        }
        return Array(storage[writeIndex...]) + Array(storage[..<writeIndex])
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
    var last: T? { storage.isEmpty ? nil : storage[(writeIndex - 1 + storage.count) % storage.count] }
}
