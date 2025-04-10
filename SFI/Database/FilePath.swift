import Foundation

class FilePath {
    // MARK: - 常量定义
    
    /// 应用包标识（例如：org.sagernet.sfi）
    static let packageName = "org.sagernet.sfi"
    
    /// App Group 标识（基于包名生成）
    static let groupName = "group.\(packageName)"
    
    // MARK: - 目录路径
    
    /// 共享目录（App Group 容器目录）
    /// - 用途：主应用与扩展（如 VPN 扩展）共享文件
    static let sharedDirectory: URL! = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupName
    )
    
    /// 缓存目录（位于共享目录下的 `Library/Caches`）
    /// - 用途：存储临时文件、缓存数据
    static let cacheDirectory = sharedDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)
    
    /// 工作目录（位于缓存目录下的 `Working`）
    /// - 用途：存储 VPN 运行时需要的配置文件、状态文件等
    static let workingDirectory = cacheDirectory.appendingPathComponent(
        "Working", 
        isDirectory: true
    )
    
    /// iCloud 目录（如果用户启用了 iCloud）
    /// - 用途：可选存储需要同步到 iCloud 的文件
    static let iCloudDirectory = FileManager.default.url(
        forUbiquityContainerIdentifier: nil
    )!.appendingPathComponent("Documents", isDirectory: true)
    
    // MARK: - 方法
    
    /// 清理目录（删除配置文件和 ProfileManager 数据）
    static func destroy() {
        // 删除共享目录下的 configs 文件夹
        try? FileManager.default.removeItem(
            at: sharedDirectory.appendingPathComponent("configs", isDirectory: true)
        )
        // 调用 ProfileManager 的清理方法
        ProfileManager.destroy()
    }
}

// MARK: - URL 扩展（文件名提取）
extension URL {
    /// 获取文件名的便捷属性
    /// 示例：`/path/to/file.txt` → `file.txt`
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}

// MARK: - URL 扩展（目录大小计算）
extension URL {
    /// 计算目录大小并格式化为可读字符串（如 "12.5 MB"）
    func formattedSize() throws -> String? {
        // 获取目录下所有文件的 URL
        guard let urls = FileManager.default.enumerator(
            at: self, 
            includingPropertiesForKeys: nil
        )?.allObjects as? [URL] else {
            return nil
        }
        
        // 计算总大小（字节）
        let size = try urls.lazy.reduce(0) {
            try ($1.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                .totalFileAllocatedSize ?? 0) + $0
        }
        
        // 格式化为人类可读的字符串
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(for: size)
    }
}