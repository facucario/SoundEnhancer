import Foundation
import os

final class RingBuffer {
    private let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>
    private var readIndex = 0
    private var writeIndex = 0
    private let lock = OSAllocatedUnfairLock()

    init(capacity: Int) {
        var c = 1
        while c < capacity { c <<= 1 }
        self.capacity = c
        self.mask = c - 1
        storage = UnsafeMutablePointer<Float>.allocate(capacity: c)
        storage.initialize(repeating: 0, count: c)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    var availableToRead: Int {
        lock.lock()
        defer { lock.unlock() }
        return writeIndex - readIndex
    }

    var availableToWrite: Int {
        lock.lock()
        defer { lock.unlock() }
        return capacity - (writeIndex - readIndex)
    }

    @discardableResult
    func write(_ src: UnsafePointer<Float>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let n = min(count, capacity)
        let space = capacity - (writeIndex - readIndex)
        if n > space {
            readIndex += n - space
        }
        for i in 0..<n {
            storage[(writeIndex + i) & mask] = src[i]
        }
        writeIndex += n
        return n
    }

    @discardableResult
    func read(_ dst: UnsafeMutablePointer<Float>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let available = writeIndex - readIndex
        let n = min(count, available)
        for i in 0..<n {
            dst[i] = storage[(readIndex + i) & mask]
        }
        readIndex += n
        return n
    }
}
