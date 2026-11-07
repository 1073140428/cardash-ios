import Foundation

/// 从设备上的 APK 里解析应用中文名：
/// 1. unzip 出 AndroidManifest.xml（AXML）→ 找 application/@label
/// 2. 若是字符串直接用；若是资源引用（@string/app_name）再去 resources.arsc 里解析
enum ApkLabel {

    // MARK: 对外入口

    static func resolve(client: ADBClient, package: String) async -> String? {
        // 1. 包名 → APK 路径
        guard let pathRes = try? await client.shell("pm path \(package) | head -1 | cut -d: -f2") else { return nil }
        let apkPath = pathRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apkPath.isEmpty else { return nil }

        let cacheKey = "label_\(package)_\(abs(apkPath.hashValue))"
        if let cached = UserDefaults.standard.string(forKey: cacheKey), !cached.isEmpty {
            return cached
        }

        // 2. manifest 很小，走 shell 很快
        guard let manData = await unzipBase64(client: client, apk: apkPath, entry: "AndroidManifest.xml"),
              let parsed = parseManifest(manData) else { return nil }

        var label: String?
        switch parsed {
        case .text(let s):
            label = s
        case .reference(let id):
            label = await resolveReference(client: client, apk: apkPath, resId: id)
        }

        if let label = label, !label.isEmpty {
            UserDefaults.standard.set(label, forKey: cacheKey)
            return label
        }
        return nil
    }

    /// resources.arsc 有几 MB，走 shell+base64 要几分钟；改成设备端解包 + sync 拉取（约 0.5 秒）
    private static func resolveReference(client: ADBClient, apk: String, resId: UInt32) async -> String? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("adbtv_label_\(resId).arsc")
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try? await client.shell(
            "unzip -o -p '\(apk)' resources.arsc > /data/local/tmp/adbtv_lbl.arsc 2>/dev/null")
        defer { Task { _ = try? await client.shell("rm -f /data/local/tmp/adbtv_lbl.arsc") } }

        guard let n = try? await client.recv(remote: "/data/local/tmp/adbtv_lbl.arsc", to: tmp), n > 8,
              let data = try? Data(contentsOf: tmp) else { return nil }
        return resolveArsc(data, resId: resId)
    }

    private static func unzipBase64(client: ADBClient, apk: String, entry: String) async -> Data? {
        let cmd = "unzip -p '\(apk)' \(entry) 2>/dev/null | base64 | tr -d '\\n'"
        guard let r = try? await client.shell(cmd) else { return nil }
        let b64 = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b64.isEmpty else { return nil }
        return Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
    }

    // MARK: AXML

    enum LabelRef {
        case text(String)
        case reference(UInt32)
    }

    static func parseManifest(_ d: Data) -> LabelRef? {
        let bytes = [UInt8](d)
        guard bytes.count > 8, u16(bytes, 0) == 0x0003 else { return nil }

        guard let pool = stringPool(bytes, at: 8) else { return nil }

        var pos = 8
        while pos + 8 <= bytes.count {
            let type = u16(bytes, pos)
            let size = Int(u32(bytes, pos + 4))
            guard size > 0, pos + size <= bytes.count else { break }
            if type == 0x0102 {  // START_ELEMENT
                let nameIdx = Int(u32(bytes, pos + 20))
                if nameIdx < pool.count, pool[nameIdx] == "application" {
                    let attrStart = Int(u16(bytes, pos + 24))
                    let attrSize = Int(u16(bytes, pos + 26))
                    let attrCount = Int(u16(bytes, pos + 28))
                    for i in 0..<attrCount {
                        let a = pos + 16 + attrStart + i * attrSize
                        guard a + 20 <= bytes.count else { break }
                        let nameI = Int(u32(bytes, a + 4))
                        guard nameI < pool.count, pool[nameI] == "label" else { continue }
                        let raw = u32(bytes, a + 8)
                        let dataType = bytes[a + 15]
                        let data = u32(bytes, a + 16)
                        if dataType == 0x03 {
                            let idx = (raw != 0xFFFF_FFFF && Int(raw) < pool.count) ? Int(raw) : Int(data)
                            if idx < pool.count { return .text(pool[idx]) }
                            return nil
                        }
                        if dataType == 0x01 { return .reference(data) }
                        return nil
                    }
                }
            }
            pos += size
        }
        return nil
    }

    static func stringPool(_ bytes: [UInt8], at pos: Int) -> [String]? {
        guard pos + 28 <= bytes.count, u16(bytes, pos) == 0x0001 else { return nil }
        let count = Int(u32(bytes, pos + 8))
        let flags = u32(bytes, pos + 16)
        let stringsStart = Int(u32(bytes, pos + 20))
        guard count > 0, count < 200_000 else { return nil }
        var out: [String] = []
        out.reserveCapacity(count)
        let utf8 = (flags & 0x100) != 0
        for i in 0..<count {
            let offPos = pos + 28 + i * 4
            guard offPos + 4 <= bytes.count else { break }
            var p = pos + stringsStart + Int(u32(bytes, offPos))
            guard p < bytes.count else { break }
            if utf8 {
                var n = Int(bytes[p]); p += 1
                if n & 0x80 != 0 { p += 1 }
                var len = Int(bytes[p]); p += 1
                if len & 0x80 != 0 {
                    len = ((len & 0x7F) << 8) | Int(bytes[p]); p += 1
                }
                if p + len <= bytes.count, let s = String(bytes: bytes[p..<p + len], encoding: .utf8) {
                    out.append(s)
                } else { out.append("") }
            } else {
                var len = Int(u16(bytes, p)); p += 2
                if len & 0x8000 != 0 {
                    len = ((len & 0x7FFF) << 16) | Int(u16(bytes, p)); p += 2
                }
                if p + len * 2 <= bytes.count {
                    var s = ""
                    var k = 0
                    while k < len {
                        let v = UInt16(bytes[p + k * 2]) | (UInt16(bytes[p + k * 2 + 1]) << 8)
                        s.unicodeScalars.append(UnicodeScalar(v) ?? "?")
                        k += 1
                    }
                    out.append(s)
                } else { out.append("") }
            }
        }
        return out
    }

    // MARK: ARSC

    static func resolveArsc(_ d: Data, resId: UInt32) -> String? {
        let bytes = [UInt8](d)
        guard bytes.count > 12, u16(bytes, 0) == 0x0002 else { return nil }
        var pos = Int(u16(bytes, 2))

        var gpool: [String] = []
        if pos + 8 <= bytes.count, u16(bytes, pos) == 0x0001 {
            gpool = stringPool(bytes, at: pos) ?? []
            pos += Int(u32(bytes, pos + 4))
        }

        let typeId = UInt8((resId >> 16) & 0xFF)
        let entryId = Int(resId & 0xFFFF)

        while pos + 8 <= bytes.count {
            let type = u16(bytes, pos)
            let headerSize = Int(u16(bytes, pos + 2))
            let size = Int(u32(bytes, pos + 4))
            guard size > 0, pos + size <= bytes.count else { break }

            if type == 0x0200 {  // package
                var p = pos + headerSize
                let end = pos + size
                while p + 8 <= end {
                    let t = u16(bytes, p)
                    let th = Int(u16(bytes, p + 2))
                    let tc = Int(u32(bytes, p + 4))
                    guard tc > 0, p + tc <= end else { break }
                    if t == 0x0201 {  // type chunk
                        let tid = bytes[p + 8]
                        let entryCount = Int(u32(bytes, p + 12))
                        let entriesStart = Int(u32(bytes, p + 16))
                        let cfgSize = Int(u32(bytes, p + 20))
                        if tid == typeId, entryId < entryCount, p + 20 + cfgSize <= end {
                            let cfg = Array(bytes[(p + 20)..<(p + 20 + cfgSize)])
                            let isDefault = cfgSize <= 64 && cfg.dropFirst(4).allSatisfy { $0 == 0 }
                            if isDefault {
                                let offPos = p + th + entryId * 4
                                if offPos + 4 <= end {
                                    let eoff = Int(u32(bytes, offPos))
                                    if eoff != 0xFFFF_FFFF {
                                        let ep = p + entriesStart + eoff
                                        if ep + 8 <= end {
                                            let esize = Int(u16(bytes, ep))
                                            let vp = ep + esize
                                            if vp + 8 <= end {
                                                let dataType = bytes[vp + 3]
                                                let data = Int(u32(bytes, vp + 4))
                                                if dataType == 0x03, data < gpool.count {
                                                    return gpool[data]
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    p += tc
                }
            }
            pos += size
        }
        return nil
    }

    // MARK: 小工具

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        guard o + 2 <= b.count else { return 0 }
        return UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
}
