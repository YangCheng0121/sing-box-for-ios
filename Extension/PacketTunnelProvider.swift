import Libbox  // VPN核心功能库
import NetworkExtension  // 苹果的VPN扩展框架

// 主VPN隧道提供类，处理VPN隧道操作
class PacketTunnelProvider: NEPacketTunnelProvider {
    // 管理不同服务器组件的变量
    var commandServer: LibboxCommandServer!  // 处理来自主应用的命令
    var boxService: LibboxBoxService!       // 核心VPN服务
    var pprofServer: LibboxPProfServer!     // 性能分析服务器（仅调试用）

    // 启动VPN隧道的主方法
    override func startTunnel(options _: [String: NSObject]?) async throws {
        var error: NSError?
        // 重定向错误日志到文件
        LibboxRedirectStderr(FilePath.cacheDirectory.appendingPathComponent("stderr.log").relativePath, &error)

        if let error {
            writeMessage("(packet-tunnel) 重定向stderr错误: \(error.localizedDescription)")
        }

        // 设置内存限制（如果未禁用）
        if !SharedPreferences.disableMemoryLimit {
            LibboxSetMemoryLimit(true)
        }

        // 启动命令服务器
        commandServer = LibboxNewCommandServer(FilePath.sharedDirectory.relativePath, serverInterface(self), 100)
        do {
            try commandServer.start()
        } catch {
            NSLog("(packet-tunnel): 日志服务器启动错误: \(error.localizedDescription)")
            return
        }
        commandServer.writeMessage("(packet-tunnel) 日志服务器已启动")

        #if DEBUG
            // 调试模式下启动性能分析服务器
            if SharedPreferences.pprofServerEnabled {
                pprofServer = LibboxNewPProfServer(SharedPreferences.pprofServerPort)
                do {
                    try pprofServer.start()
                } catch {
                    writeMessage("(packet-tunnel) 错误: 启动pprof服务器: \(error.localizedDescription)")
                    return
                }
            }
        #endif

        // 创建工作目录
        do {
            try FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        } catch {
            writeMessage("(packet-tunnel) 错误: 创建工作目录: \(error.localizedDescription)")
            return
        }

        // 初始化Libbox库
        LibboxSetup(FilePath.workingDirectory.relativePath, FilePath.cacheDirectory.relativePath, -1, -1)

        // 启动VPN服务
        startService()
    }

    // 辅助方法：写入日志消息
    private func writeMessage(_ message: String) {
        if let commandServer {
            commandServer.writeMessage(message)
        } else {
            NSLog(message)
        }
    }

    // 启动VPN核心服务
    private func startService() {
        let profile: ConfigProfile?
        do {
            // 获取选中的配置文件
            profile = try ProfileManager.shared().get(profileID: Int64(SharedPreferences.selectedProfileID))
        } catch {
            writeMessage("(packet-tunnel) 错误: 获取默认配置文件: \(error.localizedDescription)")
            return
        }
        guard let profile else {
            writeMessage("(packet-tunnel) 错误: 找不到默认配置文件")
            return
        }
        
        // 读取配置文件内容
        let configContent: String
        do {
            configContent = try profile.readContent()
        } catch {
            writeMessage("(packet-tunnel) 错误: 读取配置文件: \(error.localizedDescription)")
            return
        }
        
        // 创建VPN服务实例
        var error: NSError?
        let service = LibboxNewService(configContent, PlatformInterface(self, commandServer), &error)
        if let error {
            writeMessage("(packet-tunnel) 错误: 创建服务: \(error.localizedDescription)")
            return
        }
        guard let service else {
            return
        }

        // 启动VPN服务
        do {
            try service.start()
        } catch {
            writeMessage("(packet-tunnel) 错误: 启动服务: \(error.localizedDescription)")
            return
        }
        boxService = service
    }

    // 停止VPN服务
    private func stopService() {
        if let service = boxService {
            do {
                try service.close()
            } catch {
                writeMessage("(packet-tunnel) 错误: 停止服务: \(error.localizedDescription)")
            }
            boxService = nil
        }
    }

    // 重新加载服务（配置更新时调用）
    private func reloadService() {
        writeMessage("(packet-tunnel) 重新加载服务")
        reasserting = true  // 标记为正在重新连接
        defer {
            reasserting = false
        }
        stopService()
        startService()
    }

    // 停止VPN隧道（系统调用）
    override func stopTunnel(with reason: NEProviderStopReason) async {
        writeMessage("(packet-tunnel) 正在停止, 原因: \(reason)")
        stopService()
        // 关闭性能分析服务器
        if let server = pprofServer {
            do {
                try server.close()
            } catch {
                writeMessage("(packet-tunnel) 错误: 停止pprof服务器: \(error.localizedDescription)")
            }
            pprofServer = nil
        }
        // 关闭命令服务器
        if let server = commandServer {
            try? server.close()
            commandServer = nil
        }
    }

    // 处理来自主应用的消息
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        messageData
    }

    // 系统休眠时调用
    override func sleep() async {}

    // 系统唤醒时调用
    override func wake() {}

    // 命令服务器接口实现
    class serverInterface: NSObject, LibboxCommandServerHandlerProtocol {
        unowned let tunnel: PacketTunnelProvider  // 弱引用主隧道实例

        init(_ tunnel: PacketTunnelProvider) {
            self.tunnel = tunnel
            super.init()
        }

        // 重新加载服务（响应命令）
        func serviceReload() throws {
            tunnel.reloadService()
        }

        // 停止服务（响应命令）
        func serviceStop() throws {
            tunnel.stopService()
            tunnel.writeMessage("(packet-tunnel) 调试: 服务已停止")
        }
    }
}