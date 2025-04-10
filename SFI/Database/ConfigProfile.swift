import Foundation
import GRDB

/// 配置档案模型类（继承 GRDB 的 Record 协议，支持数据库操作）
class ConfigProfile: Record, Identifiable, ObservableObject {
    // MARK: - 属性
    
    /// 数据库主键（自动增长）
    var id: Int64?
    
    /// 配置名称（Published 修饰，支持 SwiftUI 数据绑定）
    @Published var name: String
    
    /// 排序字段（用于界面显示顺序）
    var order: UInt32
    
    /// 配置类型（本地/iCloud/远程）
    var type: ProfileType
    
    /// 文件路径（本地路径或 iCloud 文件名）
    var path: String
    
    /// 远程 URL（仅当 type == .remote 时有效）
    @Published var remoteURL: String?
    
    /// 是否自动更新（仅远程配置有效）
    @Published var autoUpdate: Bool
    
    /// 最后更新时间（仅远程配置有效）
    var lastUpdated: Date?

    // MARK: - 配置类型枚举
    enum ProfileType: Int {
        case local = 0  // 本地文件
        case icloud     // iCloud 文件
        case remote     // 远程配置文件
    }

    // MARK: - 初始化方法
    
    /// 初始化配置档案
    init(
        id: Int64? = nil,
        name: String,
        order: UInt32 = 0,
        type: ProfileType,
        path: String,
        remoteURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.type = type
        self.path = path
        self.remoteURL = remoteURL
        
        // 默认值设置
        self.autoUpdate = false
        self.lastUpdated = nil
        
        // 如果是远程配置，设置初始更新时间
        if type == .remote {
            self.lastUpdated = Date()
        }
        
        super.init()
    }

    // MARK: - 数据库配置
    
    /// 定义数据库表名
    override class var databaseTableName: String {
        "profiles"
    }
    
    /// 定义数据库列名（与表结构对应）
    enum Columns: String, ColumnExpression {
        case id          // 主键
        case name        // 配置名称
        case order       // 排序字段
        case type        // 配置类型
        case path        // 文件路径
        case remoteURL   // 远程URL
        case autoUpdate  // 自动更新标志
        case lastUpdated // 最后更新时间
        case userAgent   // 预留字段（未使用）
    }

    // MARK: - 数据库解码（从数据库读取记录）
    
    /// 从数据库行数据初始化对象
    required init(row: Row) throws {
        self.id = row[Columns.id]
        self.name = row[Columns.name]
        self.order = row[Columns.order]
        self.type = ProfileType(rawValue: row[Columns.type])! // 强制解包需确保值有效
        self.path = row[Columns.path]
        self.remoteURL = row[Columns.remoteURL]
        self.autoUpdate = row[Columns.autoUpdate]
        self.lastUpdated = row[Columns.lastUpdated]
        try super.init(row: row)
    }

    // MARK: - 数据库编码（保存到数据库）
    
    /// 将对象数据编码到数据库容器
    override func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.order] = order
        container[Columns.type] = type.rawValue
        container[Columns.path] = path
        container[Columns.remoteURL] = remoteURL
        container[Columns.autoUpdate] = autoUpdate
        container[Columns.lastUpdated] = lastUpdated
    }

    // MARK: - 数据库回调
    
    /// 插入数据后的回调（获取自动生成的主键）
    override func didInsert(_ inserted: InsertionSuccess) {
        super.didInsert(inserted)
        id = inserted.rowID
    }

    // MARK: - 文件操作
    
    /// 读取配置文件内容
    func readContent() throws -> String {
        switch type {
        case .local, .remote:
            // 本地/远程文件：直接读取路径文件内容
            return try String(contentsOfFile: path)
            
        case .icloud:
            // iCloud 文件：需要安全访问权限
            let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
            saveURL.startAccessingSecurityScopedResource()
            defer {
                saveURL.stopAccessingSecurityScopedResource()
            }
            return try String(contentsOf: saveURL)
        }
    }
    
    /// 保存配置文件内容
    func saveContent(_ content: String) throws {
        switch type {
        case .local, .remote:
            // 本地/远程文件：直接写入路径文件
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            
        case .icloud:
            // iCloud 文件：需要安全访问权限
            let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
            saveURL.startAccessingSecurityScopedResource()
            defer {
                saveURL.stopAccessingSecurityScopedResource()
            }
            try content.write(to: saveURL, atomically: true, encoding: .utf8)
        }
    }
}