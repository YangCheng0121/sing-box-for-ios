import Foundation
import Libbox
import NetworkExtension

/// 实现 Libbox 平台接口协议，用于桥接 iOS 网络扩展功能
class PlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    // MARK: - 属性
    let tunnel: NEPacketTunnelProvider  // 隧道提供者实例
    let commandServer: LibboxCommandServer  // 命令服务器（用于日志输出）

    // MARK: - 初始化
    init(_ tunnel: NEPacketTunnelProvider, _ logServer: LibboxCommandServer) {
        self.tunnel = tunnel
        self.commandServer = logServer
    }

    // MARK: - 核心方法
    
    /// 打开 TUN 设备并配置网络参数
    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else {
            throw NSError(domain: "nil options", code: 0) // 参数检查
        }
        guard let ret0_ else {
            throw NSError(domain: "nil return pointer", code: 0)
        }

        // 创建隧道网络设置（远程地址无实际作用）
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // 自动路由配置（核心功能）
        if options.getAutoRoute() {
            // 设置 MTU
            settings.mtu = NSNumber(value: options.getMTU())

            // DNS 配置
            var error: NSError?
            let dnsServer = options.getDNSServerAddress(&error)
            if let error {
                throw error
            }
            settings.dnsSettings = NEDNSSettings(servers: [dnsServer])

            // IPv4 地址配置
            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            let ipv4AddressIterator = options.getInet4Address()!
            while ipv4AddressIterator.hasNext() {
                let ipv4Prefix = ipv4AddressIterator.next()!
                ipv4Address.append(ipv4Prefix.address)    // 地址
                ipv4Mask.append(ipv4Prefix.mask())       // 子网掩码
            }
            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            
            // IPv4 路由配置
            var ipv4Routes: [NEIPv4Route] = []
            let inet4RouteAddressIterator = options.getInet4RouteAddress()!
            if inet4RouteAddressIterator.hasNext() {
                // 添加自定义路由
                while inet4RouteAddressIterator.hasNext() {
                    let ipv4RoutePrefix = inet4RouteAddressIterator.next()!
                    ipv4Routes.append(NEIPv4Route(
                        destinationAddress: ipv4RoutePrefix.address,
                        subnetMask: ipv4RoutePrefix.mask()
                    ))
                }
            } else {
                // 默认路由
                ipv4Routes.append(NEIPv4Route.default())
            }
            // 包含本地地址路由
            for (index, address) in ipv4Address.enumerated() {
                ipv4Routes.append(NEIPv4Route(
                    destinationAddress: address,
                    subnetMask: ipv4Mask[index]
                ))
            }
            ipv4Settings.includedRoutes = ipv4Routes
            settings.ipv4Settings = ipv4Settings

            // IPv6 配置（逻辑类似 IPv4）
            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            let ipv6AddressIterator = options.getInet6Address()!
            while ipv6AddressIterator.hasNext() {
                let ipv6Prefix = ipv6AddressIterator.next()!
                ipv6Address.append(ipv6Prefix.address)
                ipv6Prefixes.append(NSNumber(value: ipv6Prefix.prefix))
            }
            let ipv6Settings = NEIPv6Settings(
                addresses: ipv6Address,
                networkPrefixLengths: ipv6Prefixes
            )
            
            // IPv6 路由配置
            var ipv6Routes: [NEIPv6Route] = []
            let inet6RouteAddressIterator = options.getInet6RouteAddress()!
            if inet6RouteAddressIterator.hasNext() {
                while inet6RouteAddressIterator.hasNext() {
                    let ipv6RoutePrefix = inet4RouteAddressIterator.next()! // 疑似类型错误？
                    ipv6Routes.append(NEIPv6Route(
                        destinationAddress: ipv6RoutePrefix.description,
                        networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix)
                    ))
                }
            } else {
                ipv6Routes.append(NEIPv6Route.default())
            }
            ipv6Settings.includedRoutes = ipv6Routes
            settings.ipv6Settings = ipv6Settings
        }

        // HTTP 代理配置（如启用）
        if options.isHTTPProxyEnabled() {
            let proxySettings = NEProxySettings()
            let proxyServer = NEProxyServer(
                address: options.getHTTPProxyServer(),
                port: Int(options.getHTTPProxyServerPort())
            )
            proxySettings.httpEnabled = true
            proxySettings.httpServer = proxyServer
            proxySettings.httpsEnabled = true
            proxySettings.httpsServer = proxyServer
            settings.proxySettings = proxySettings
        }

        // 应用网络设置（关键步骤）
        try runBlocking { [self] in
            try await tunnel.setTunnelNetworkSettings(settings)
        }

        // 获取 TUN 文件描述符（用于数据包转发）
        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd  // 通过指针返回文件描述符
            return
        }

        // 备选获取方式（通过 Libbox 内部方法）
        let tunFdFromLoop = LibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            ret0_.pointee = tunFdFromLoop
        } else {
            throw NSError(domain: "missing file descriptor", code: 0)
        }
    }

    // MARK: - 协议方法实现
    
    /// 是否使用平台自动检测控制（返回 true 表示使用 iOS 系统路由）
    func usePlatformAutoDetectControl() -> Bool {
        true
    }

    /// 自动检测控制（未实现）
    func autoDetectControl(_: Int32) throws {
        // 留空表示不处理
    }

    /// 查找连接所有者（未实现）
    func findConnectionOwner(
        _: Int32,
        sourceAddress _: String?,
        sourcePort _: Int32,
        destinationAddress _: String?,
        destinationPort _: Int32,
        ret0_ _: UnsafeMutablePointer<Int32>?
    ) throws {
        throw NSError(domain: "not implemented", code: 0)
    }

    /// 通过 UID 获取包名（返回空字符串）
    func packageName(byUid _: Int32, error _: NSErrorPointer) -> String {
        "" // iOS 安全限制无法实现
    }

    /// 通过包名获取 UID（未实现）
    func uid(byPackageName _: String?, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "not implemented", code: 0)
    }

    /// 是否使用 proc 文件系统（返回 false）
    func useProcFS() -> Bool {
        false // iOS 无 procfs
    }

    /// 写入日志到命令服务器
    func writeLog(_ message: String?) {
        guard let message else { return }
        commandServer.writeMessage(message) // 转发到日志服务器
    }

    /// 是否使用平台默认接口监控（返回 false）
    func usePlatformDefaultInterfaceMonitor() -> Bool {
        false
    }

    /// 启动默认接口监控（未实现）
    func startDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        // 留空表示不监控
    }

    /// 关闭默认接口监控（未实现）
    func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        // 留空
    }

    /// 是否使用 Getter 方法（返回 false）
    func useGetter() -> Bool {
        false
    }

    /// 获取网络接口列表（未实现）
    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "not implemented", code: 0)
    }

    /// 是否在 Network Extension 环境下运行（返回 true）
    func underNetworkExtension() -> Bool {
        true // 标识当前运行在扩展环境
    }
}