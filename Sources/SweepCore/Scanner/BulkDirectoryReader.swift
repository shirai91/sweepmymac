import Darwin

enum ObjectType {
    static let regular: UInt32 = 1
    static let directory: UInt32 = 2
    static let symlink: UInt32 = 5
}

struct RawEntry {
    var name = ""
    var objectType: UInt32 = 0
    var deviceID: Int32 = 0
    var modificationTime: Int64 = 0
    var accessTime: Int64 = 0
    var fileID: UInt64 = 0
    var linkCount: UInt32 = 1
    var allocatedSize: Int64 = 0

    var isDirectory: Bool { objectType == ObjectType.directory }
}

private enum AttributeBit {
    static let name: UInt32 = 0x0000_0001
    static let deviceID: UInt32 = 0x0000_0002
    static let objectType: UInt32 = 0x0000_0008
    static let modificationTime: UInt32 = 0x0000_0400
    static let accessTime: UInt32 = 0x0000_1000
    static let fileID: UInt32 = 0x0200_0000
    static let error: UInt32 = 0x2000_0000
    static let returnedAttributes: UInt32 = 0x8000_0000
    static let fileLinkCount: UInt32 = 0x0000_0001
    static let fileAllocatedSize: UInt32 = 0x0000_0004
}

final class BulkDirectoryReader {
    private let buffer: UnsafeMutableRawPointer
    private let capacity: Int
    private var request: attrlist

    init(capacity: Int = 256 * 1024) {
        self.capacity = capacity
        buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        request = attrlist(
            bitmapcount: u_short(ATTR_BIT_MAP_COUNT),
            reserved: 0,
            commonattr: AttributeBit.returnedAttributes | AttributeBit.name | AttributeBit.error | AttributeBit.deviceID
                | AttributeBit.objectType | AttributeBit.modificationTime | AttributeBit.accessTime | AttributeBit.fileID,
            volattr: 0,
            dirattr: 0,
            fileattr: AttributeBit.fileLinkCount | AttributeBit.fileAllocatedSize,
            forkattr: 0
        )
    }

    deinit { buffer.deallocate() }

    static func openDirectory(_ path: String) -> Int32 {
        open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }

    static func openDirectory(named name: String, in parent: Int32) -> Int32 {
        openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }

    func read(directory path: String, _ visit: (inout RawEntry) -> Void) -> Bool {
        let fd = Self.openDirectory(path)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        read(descriptor: fd, visit)
        return true
    }

    func read(descriptor fd: Int32, _ visit: (inout RawEntry) -> Void) {
        var entry = RawEntry()
        while true {
            let count = getattrlistbulk(fd, &request, buffer, capacity, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            var cursor = UnsafeRawPointer(buffer)
            for _ in 0..<Int(count) {
                let length = Int(cursor.loadUnaligned(as: UInt32.self))
                if decode(entryAt: cursor, into: &entry) {
                    visit(&entry)
                }
                cursor += length
            }
        }
    }

    private func decode(entryAt start: UnsafeRawPointer, into entry: inout RawEntry) -> Bool {
        var field = start + 4
        let common = field.loadUnaligned(as: UInt32.self)
        let file = field.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
        field += 20
        if common & AttributeBit.error != 0 {
            let failure = field.loadUnaligned(as: UInt32.self)
            field += 4
            if failure != 0 { return false }
        }
        guard common & AttributeBit.name != 0 else { return false }
        let nameOffset = Int(field.loadUnaligned(as: Int32.self))
        let nameLength = Int(field.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        entry.name = String(decoding: UnsafeRawBufferPointer(start: field + nameOffset, count: max(0, nameLength - 1)), as: UTF8.self)
        field += 8
        if common & AttributeBit.deviceID != 0 {
            entry.deviceID = field.loadUnaligned(as: Int32.self)
            field += 4
        }
        entry.objectType = 0
        if common & AttributeBit.objectType != 0 {
            entry.objectType = field.loadUnaligned(as: UInt32.self)
            field += 4
        }
        entry.modificationTime = 0
        if common & AttributeBit.modificationTime != 0 {
            entry.modificationTime = field.loadUnaligned(as: Int64.self)
            field += 16
        }
        entry.accessTime = 0
        if common & AttributeBit.accessTime != 0 {
            entry.accessTime = field.loadUnaligned(as: Int64.self)
            field += 16
        }
        entry.fileID = 0
        if common & AttributeBit.fileID != 0 {
            entry.fileID = field.loadUnaligned(as: UInt64.self)
            field += 8
        }
        entry.linkCount = 1
        if file & AttributeBit.fileLinkCount != 0 {
            entry.linkCount = field.loadUnaligned(as: UInt32.self)
            field += 4
        }
        entry.allocatedSize = 0
        if file & AttributeBit.fileAllocatedSize != 0 {
            entry.allocatedSize = field.loadUnaligned(as: Int64.self)
        }
        return true
    }
}
