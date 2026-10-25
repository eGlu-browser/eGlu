import Darwin
import Foundation

/// The HTTP servers running on this Mac, for the command bar while the
/// text typed is "local", "localhost", ":" or a port's first digits
/// (Decided 8): the TCP ports the person's own processes listen on, on
/// 127.0.0.1, ::1, 0.0.0.0 or ::, that answer a `HEAD /` in time. The
/// listening sockets are read through libproc, off the main actor, and
/// the answer is kept two seconds so a word typed letter by letter asks
/// once, not once a letter.
enum LocalServers {
    /// A port that answered HTTP, and the name of the process on it.
    struct Server: Sendable, Equatable {
        let port: Int
        let name: String
    }

    /// Whether the servers are asked for this text at all: "local",
    /// "localhost", ":" or a port's first digits, as Decided 8 has it.
    static func asks(_ text: String) -> Bool {
        let typed = text.trimmingCharacters(in: .whitespaces).lowercased()
        return typed == "local" || typed == "localhost"
            || typed.hasPrefix(":") || typed.hasPrefix("localhost:")
            || (!typed.isEmpty && typed.allSatisfy { $0.isNumber })
    }

    /// Of the servers found, the ones the text still names: every one for
    /// "local" or "localhost", a port's first digits for ":" or digits.
    static func filter(_ servers: [Server], for text: String) -> [Server] {
        let typed = text.trimmingCharacters(in: .whitespaces).lowercased()
        var digits = ""
        if typed.hasPrefix("localhost:") { digits = String(typed.dropFirst("localhost:".count)) }
        else if typed.hasPrefix(":") { digits = String(typed.dropFirst()) }
        else if !typed.isEmpty, typed.allSatisfy({ $0.isNumber }) { digits = typed }
        guard !digits.isEmpty else { return servers }
        return servers.filter { String($0.port).hasPrefix(digits) }
    }

    /// The latest scan and probe's answer, kept two seconds.
    private static var last: (when: Date, servers: [Server])?

    /// The listening ports that answer HTTP. Off the main actor: the scan
    /// walks every process's sockets, which takes a moment.
    static func listen() async -> [Server] {
        if let last, Date().timeIntervalSince(last.when) < 2 { return last.servers }
        let found = await Task.detached(priority: .utility, operation: scan).value
        let servers = await probe(found)
        last = (Date(), servers)
        return servers
    }

    /// Every TCP socket in LISTEN on a loopback or wildcard address of a
    /// readable process, its port and the process's name. A process that
    /// cannot be read is left out, not the scan.
    private static func scan() -> [(port: Int, name: String)] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard bytes > 0 else { return [] }
        var ports: [(Int, String)] = []
        var seen: Set<Int> = []
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid != 0 {
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: 1024)
            let fdBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(MemoryLayout<proc_fdinfo>.stride * fds.count))
            guard fdBytes > 0 else { continue }
            for fd in fds.prefix(Int(fdBytes) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                var socket = socket_fdinfo()
                let size = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socket, Int32(MemoryLayout<socket_fdinfo>.size))
                guard size == Int32(MemoryLayout<socket_fdinfo>.size), socket.psi.soi_kind == SOCKINFO_TCP else { continue }
                let tcp = socket.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == TSI_S_LISTEN, local(tcp.tcpsi_ini) else { continue }
                // insi_lport is the port in network byte order.
                let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
                guard port != 0, seen.insert(port).inserted else { continue }
                ports.append((port, processName(of: pid)))
            }
        }
        return ports
    }

    /// Whether the socket listens on 127.0.0.1, ::1, 0.0.0.0 or ::.
    private static func local(_ socket: in_sockinfo) -> Bool {
        if Int32(socket.insi_vflag) & INI_IPV6 != 0 {
            return withUnsafeBytes(of: socket.insi_laddr.ina_6) { bytes in
                if bytes.allSatisfy({ $0 == 0 }) { return true }
                if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes.last == 1 { return true }
                // A v4-mapped v6 address: ::ffff:127.0.0.1 or ::ffff:0.0.0.0.
                guard bytes.count == 16, bytes.prefix(10).allSatisfy({ $0 == 0 }),
                      bytes[10] == 0xff, bytes[11] == 0xff else { return false }
                let v4 = bytes[12...15]
                return v4.allSatisfy({ $0 == 0 }) || (v4.first == 127 && v4.dropFirst().allSatisfy({ $0 == 0 }))
            }
        }
        if Int32(socket.insi_vflag) & INI_IPV4 != 0 {
            let address = socket.insi_laddr.ina_46.i46a_addr4.s_addr
            return address == in_addr_t(INADDR_ANY) || address == in_addr_t(INADDR_LOOPBACK).bigEndian
        }
        return false
    }

    /// The process's own name for a row's second line: its executable's.
    private static func processName(of pid: pid_t) -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0,
           let name = URL(fileURLWithPath: String(cString: path)).lastPathComponent.isEmpty ? nil
               : URL(fileURLWithPath: String(cString: path)).lastPathComponent {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// HEAD / on each port, at most 32 asked at once, 300 ms to answer.
    /// Any HTTP answer makes the port a server, whatever its status.
    private static func probe(_ ports: [(port: Int, name: String)]) async -> [Server] {
        var answered: [Server] = []
        var index = ports.startIndex
        while index < ports.endIndex {
            let slice = ports[index ..< min(index + 32, ports.endIndex)]
            index = slice.endIndex
            await withTaskGroup(of: Server?.self) { group in
                for candidate in slice {
                    group.addTask { await answer(candidate) }
                }
                for await server in group {
                    if let server { answered.append(server) }
                }
            }
        }
        return answered.sorted { $0.port < $1.port }
    }

    /// Cookies and cache are disabled. The server on the Mac itself still
    /// receives the request and its connection metadata.
    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 0.3
        return URLSession(configuration: configuration)
    }()

    private static func answer(_ candidate: (port: Int, name: String)) async -> Server? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(candidate.port)/")!)
        request.httpMethod = "HEAD"
        guard let reply = try? await probeSession.data(for: request).1,
              reply is HTTPURLResponse else { return nil }
        return Server(port: candidate.port, name: candidate.name)
    }
}
