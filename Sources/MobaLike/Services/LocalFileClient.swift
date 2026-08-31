import Foundation

/// 本地文件浏览器后端（本地终端用）：直接操作本地文件系统，无需 sftp
final class LocalFileClient: FileClient {
    var identity: String { "local" }

    func home() -> (String, String?) {
        (NSHomeDirectory(), nil)
    }

    func list(path: String) -> ([SftpEntry], String?) {
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: path)
            var entries: [SftpEntry] = []
            for name in items {
                let full = (path as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
                var size: Int64 = 0
                if !isDir.boolValue,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: full),
                   let sz = attrs[.size] as? NSNumber {
                    size = sz.int64Value
                }
                entries.append(SftpEntry(name: name, isDirectory: isDir.boolValue, size: size, perms: ""))
            }
            return (entries, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    func put(local: String, remote: String) -> String? {
        do {
            try FileManager.default.copyItem(atPath: local, toPath: remote)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func get(remote: String, local: String) -> String? {
        do {
            try FileManager.default.copyItem(atPath: remote, toPath: local)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func mkdir(path: String) -> String? {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeFile(path: String) -> String? {
        do {
            try FileManager.default.removeItem(atPath: path)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeDir(path: String) -> String? {
        removeFile(path: path)   // 本地可整目录删除（界面有确认）
    }

    func rename(from old: String, to new: String) -> String? {
        do {
            try FileManager.default.moveItem(atPath: old, toPath: new)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
