import Darwin
import Foundation
import PadCore

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

    /// Whether the servers are asked for this text at all
    /// (DeveloperMode.localServerDigits).
    static func asks(_ text: String) -> Bool {
        DeveloperMode.localServerDigits(text) != nil
    }

    /// Of the servers found, the ones the text still names: every one for
    /// "local" or "localhost", a port's first digits for ":" or digits.
    static func filter(_ servers: [Server], for text: String) -> [Server] {
        guard let digits = DeveloperMode.localServerDigits(text) else { return [] }
        guard !digits.isEmpty else { return servers }
        return servers.filter { String($0.port).hasPrefix(digits) }
    }

    /// The listening ports that answer HTTP. Off the main actor: the scan
    /// walks every process's sockets, which takes a moment.
    static func listen() async -> [Server] {
        await finder.servers()
    }

    /// The one scan at a time, and its answer for two seconds: windows
    /// asking together, and letters typed while a scan runs, wait for it
    /// rather than start their own.
    private actor Finder {
        private var last: (when: Date, servers: [Server])?
        private var running: Task<[Server], Never>?

        func servers() async -> [Server] {
            if let last, Date().timeIntervalSince(last.when) < 2 { return last.servers }
            if let running { return await running.value }
            let scan = Task.detached(priority: .utility) { await LocalServers.probe(LocalServers.scan()) }
            running = scan
            let found = await scan.value
            last = (Date(), found)
            running = nil
            return found
        }
    }

    private static let finder = Finder()

    /// A listening port, the process's name, and whether anything listens
    /// on it over IPv4: one that listens over IPv6 alone is asked at ::1.
    struct Listener: Sendable {
        let port: Int
        let name: String
        var ipv4: Bool
    }

    /// Every TCP socket in LISTEN on a loopback or wildcard address of a
    /// readable process, its port and the process's name. A process that
    /// cannot be read is left out, not the scan.
    fileprivate static func scan() -> [Listener] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard bytes > 0 else { return [] }
        var listeners: [Listener] = []
        var at: [Int: Int] = [:]
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid != 0 {
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: 1024)
            let fdBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(MemoryLayout<proc_fdinfo>.stride * fds.count))
            guard fdBytes > 0 else { continue }
            for fd in fds.prefix(Int(fdBytes) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                var socket = socket_fdinfo()
                let size = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socket, Int32(MemoryLayout<socket_fdinfo>.size))
                guard size == Int32(MemoryLayout<socket_fdinfo>.size), socket.psi.soi_kind == SOCKINFO_TCP else { continue }
                let tcp = socket.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == TSI_S_LISTEN, let family = local(tcp.tcpsi_ini) else { continue }
                // insi_lport is the port in network byte order.
                let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
                guard port != 0 else { continue }
                if let index = at[port] {
                    listeners[index].ipv4 = listeners[index].ipv4 || family == .ipv4
                } else {
                    at[port] = listeners.count
                    listeners.append(Listener(port: port, name: processName(of: pid), ipv4: family == .ipv4))
                }
            }
        }
        return listeners
    }

    private enum Family { case ipv4, ipv6 }

    /// How the socket listens on 127.0.0.1, ::1, 0.0.0.0 or ::, or nil for
    /// any other address. A v4-mapped v6 address is v4.
    private static func local(_ socket: in_sockinfo) -> Family? {
        if Int32(socket.insi_vflag) & INI_IPV6 != 0 {
            return withUnsafeBytes(of: socket.insi_laddr.ina_6) { bytes -> Family? in
                if bytes.allSatisfy({ $0 == 0 }) { return .ipv6 }
                if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes.last == 1 { return .ipv6 }
                // ::ffff:127.0.0.1 or ::ffff:0.0.0.0.
                guard bytes.count == 16, bytes.prefix(10).allSatisfy({ $0 == 0 }),
                      bytes[10] == 0xff, bytes[11] == 0xff else { return nil }
                let v4 = bytes[12...15]
                return v4.allSatisfy({ $0 == 0 }) || (v4.first == 127 && v4.dropFirst().allSatisfy({ $0 == 0 })) ? .ipv4 : nil
            }
        }
        if Int32(socket.insi_vflag) & INI_IPV4 != 0 {
            let address = socket.insi_laddr.ina_46.i46a_addr4.s_addr
            return address == in_addr_t(INADDR_ANY) || address == in_addr_t(INADDR_LOOPBACK).bigEndian ? .ipv4 : nil
        }
        return nil
    }

    /// The process's own name for a row's second line: its executable's.
    private static func processName(of pid: pid_t) -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let name = URL(fileURLWithPath: String(cString: path)).lastPathComponent
            if !name.isEmpty { return name }
        }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// HEAD / on each port, at most 32 asked at once, 300 ms to answer.
    /// Any HTTP answer makes the port a server, whatever its status.
    fileprivate static func probe(_ listeners: [Listener]) async -> [Server] {
        var answered: [Server] = []
        var index = listeners.startIndex
        while index < listeners.endIndex {
            let slice = listeners[index ..< min(index + 32, listeners.endIndex)]
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

    /// Cookies and cache are disabled, and 300 ms is the whole answer's
    /// time, not only the wait between bytes. The server on the Mac itself
    /// still receives the request and its connection metadata.
    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 0.3
        configuration.timeoutIntervalForResource = 0.3
        return URLSession(configuration: configuration)
    }()

    /// A redirect's answer is the answer: nothing is asked of the address
    /// a local server sends the probe to, which may be anywhere (nothing
    /// leaves the Mac but the pages the person opens).
    private final class Unredirected: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            nil
        }
    }

    private static let unredirected = Unredirected()

    private static func answer(_ candidate: Listener) async -> Server? {
        let host = candidate.ipv4 ? "127.0.0.1" : "[::1]"
        guard let url = URL(string: "http://\(host):\(candidate.port)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let reply = try? await probeSession.data(for: request, delegate: unredirected).1,
              reply is HTTPURLResponse else { return nil }
        return Server(port: candidate.port, name: candidate.name)
    }
}
