//
//  CircularBuffer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import Foundation

/// 这个是单生产者，多消费者的阻塞队列和单生产者，多消费者的阻塞环形队列。并且环形队列还要有排序的能力。
/// 因为seek需要清空队列，所以导致他是多消费者。后续可以看下能不能改成单消费者的。
public class CircularBuffer<Item: ObjectQueueItem> {
    private var _buffer = ContiguousArray<Item?>()
//    private let semaphore = DispatchSemaphore(value: 0)
    private let condition = NSCondition()
    private var headIndex = UInt(0)
    private var tailIndex = UInt(0)
    private let expanding: Bool
    private let sorted: Bool
    private let isClearItem: Bool
    private var destroyed = false
    @inline(__always)
    private var _count: Int { Int(tailIndex &- headIndex) }
    @inline(__always)
    public var count: Int {
        condition.lock()
        defer { condition.unlock() }
        return Int(tailIndex &- headIndex)
    }

    public internal(set) var fps: Float = 24
    public private(set) var maxCount: Int
    private var mask: UInt
    public init(initialCapacity: Int = 256, sorted: Bool = false, expanding: Bool = true, isClearItem: Bool = true) {
        self.expanding = expanding
        self.sorted = sorted
        self.isClearItem = isClearItem
        let capacity = initialCapacity.nextPowerOf2()
        _buffer = ContiguousArray<Item?>(repeating: nil, count: Int(capacity))
        maxCount = Int(capacity)
        mask = UInt(maxCount - 1)
        assert(_buffer.count == capacity)
    }

    public func push(_ value: Item) {
        condition.lock()
        defer { condition.unlock() }
        if destroyed {
            return
        }
        if _buffer[Int(tailIndex & mask)] != nil {
//            assertionFailure("value is not nil of headIndex: \(headIndex),tailIndex: \(tailIndex), bufferCount: \(_buffer.count), mask: \(mask)")
        }
        _buffer[Int(tailIndex & mask)] = value
        if sorted {
            // 不用sort进行排序，这个比较高效
            var index = tailIndex
            while index > headIndex {
                guard let item = _buffer[Int((index - 1) & mask)] else {
//                    assertionFailure("value is nil of index: \((index - 1) & mask) headIndex: \(headIndex),tailIndex: \(tailIndex), bufferCount: \(_buffer.count),  mask: \(mask)")
                    break
                }
                if item.timestamp <= _buffer[Int(index & mask)]!.timestamp {
                    break
                }
                _buffer.swapAt(Int((index - 1) & mask), Int(index & mask))
                index -= 1
            }
        }
        tailIndex &+= 1
        if _count >= maxCount {
            if expanding {
                // No more room left for another append so grow the buffer now.
                _doubleCapacity()
            } else {
                condition.wait()
            }
        } else {
            // 只有数据了。就signal。因为有可能这是最后的数据了。
            if _count == 1 {
                condition.signal()
            }
        }
    }

    public func pop(wait: Bool = false, where predicate: ((Item, Int) -> Bool)? = nil) -> Item? {
        condition.lock()
        defer { condition.unlock() }
        if destroyed {
            return nil
        }
        if headIndex == tailIndex {
            if wait {
                condition.wait()
                if destroyed || headIndex == tailIndex {
                    return nil
                }
            } else {
                return nil
            }
        }
        let index = Int(headIndex & mask)
        guard let item = _buffer[index] else {
//            assertionFailure("value is nil of index: \(index) headIndex: \(headIndex),tailIndex: \(tailIndex), bufferCount: \(_buffer.count), mask: \(mask)")
            return nil
        }
        if let predicate, !predicate(item, _count) {
            return nil
        } else {
            headIndex &+= 1
            if isClearItem {
                _buffer[index] = nil
            }
            if _count == maxCount >> 1 {
                condition.signal()
            }
            return item
        }
    }

    public func search(where predicate: (Item) -> Bool) -> [Item] {
        condition.lock()
        defer { condition.unlock() }
        var i = headIndex
        var result = [Item]()
        while i < tailIndex {
            if let item = _buffer[Int(i & mask)] {
                if predicate(item) {
                    result.append(item)
                    if isClearItem {
                        _buffer[Int(i & mask)] = nil
                    }
                    headIndex = i + 1
                }
            } else {
//                assertionFailure("value is nil of index: \(i) headIndex: \(headIndex), tailIndex: \(tailIndex), bufferCount: \(_buffer.count), mask: \(mask)")
                return result
            }
            i += 1
        }
        return result
    }

    public func seek(seconds: Double, needKeyFrame: Bool = false) -> (UInt, TimeInterval)? {
        condition.lock()
        defer { condition.unlock() }
        var i = headIndex
        if let item = _buffer[Int(i & mask)] {
            let isForward = seconds > item.seconds
            if isForward {
                i += 1
                while i <= tailIndex, let item = _buffer[Int(i & mask)] {
                    if item.seconds >= seconds {
                        if needKeyFrame {
                            if let packet = item as? Packet, packet.isKeyFrame {
                                return (i, packet.seconds)
                            } else {
                                i -= 1
                                while i > headIndex {
                                    if let packet = _buffer[Int(i & mask)] as? Packet, packet.isKeyFrame {
                                        return (i, packet.seconds)
                                    }
                                    i -= 1
                                }
                                return nil
                            }
                        } else {
                            return (i, item.seconds)
                        }
                    }
                    i += 1
                }
            } else {
                while i > 0, let item = _buffer[Int(i & mask)] {
                    if item.seconds <= seconds {
                        if needKeyFrame {
                            if let packet = item as? Packet, packet.isKeyFrame {
                                return (i, packet.seconds)
                            }
                        } else {
                            return (i, item.seconds)
                        }
                    }
                    i -= 1
                }
            }
        }
        return nil
    }

    func update(headIndex: UInt) {
        condition.lock()
        defer { condition.unlock() }
        self.headIndex = headIndex
    }

    public func flush() {
        condition.lock()
        defer { condition.unlock() }
        headIndex = 0
        tailIndex = 0
        _buffer.removeAll(keepingCapacity: !destroyed)
        _buffer.append(contentsOf: ContiguousArray<Item?>(repeating: nil, count: destroyed ? 1 : maxCount))
        condition.broadcast()
    }

    public func shutdown() {
        destroyed = true
        flush()
    }

    private func _doubleCapacity() {
        var newBacking: ContiguousArray<Item?> = []
        let newCapacity = maxCount << 1 // Double the storage.
        precondition(newCapacity > 0, "Can't double capacity of \(_buffer.count)")
        assert(newCapacity % 2 == 0)
        newBacking.reserveCapacity(newCapacity)
        let head = Int(headIndex & mask)
        newBacking.append(contentsOf: _buffer[head ..< maxCount])
        if head > 0 {
            newBacking.append(contentsOf: _buffer[0 ..< head])
        }
        let repeatitionCount = newCapacity &- newBacking.count
        newBacking.append(contentsOf: repeatElement(nil, count: repeatitionCount))
        headIndex = 0
        tailIndex = UInt(newBacking.count &- repeatitionCount)
        _buffer = newBacking
        maxCount = newCapacity
        mask = UInt(maxCount - 1)
    }
}

extension FixedWidthInteger {
    /// Returns the next power of two.
    @inline(__always)
    func nextPowerOf2() -> Self {
        guard self != 0 else {
            return 1
        }
        return 1 << (Self.bitWidth - (self - 1).leadingZeroBitCount)
    }
}
