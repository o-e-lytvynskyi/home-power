import Darwin
import Foundation

/// JSON-RPC over UDP to a Marstek battery's Local API (Open API Rev 3.1).
///
/// The protocol is one datagram each way; everything difficult is timing:
/// - the firmware ignores requests for about 2 s after it has replied, so
///   calls are spaced by `quietWindow` from the last reply;
/// - over Wi-Fi requests are lost in bursts, so a call is resent at 0.5, 2.5
///   and 5 s before it is given up (taurgis/has-marstek-local-api measured
///   60 of 60 recovered this way);
/// - resends carry the same id, so a late reply to the first copy still counts.
///
/// The socket is bound to an ephemeral port. Some firmware (Venus E 2.0, E mini)
/// replies only to source port 30000, but the Venus E 3.0 on firmware 148
/// answered an ephemeral port on 2026-10-14 — and not holding 30000 leaves it to
/// any other client on this Mac.
///
/// Blocking: every call must come from one serial queue.
final class MarstekLink {

    enum Failure: Error, Equatable {
        /// Nothing came back: wrong address, station off, or Local API disabled.
        case noReply
        /// `sendto` was refused before anything left the Mac. On macOS 15+ this
        /// is what a missing Local Network permission looks like.
        case blocked(String)
        /// The address does not parse or resolve.
        case badAddress(String)
        /// The station answered with a JSON-RPC error.
        case rpc(code: Int, message: String)
        case socket(String)

        var text: String {
            switch self {
            case .noReply:              return "No reply"
            case .blocked(let why):     return why
            case .badAddress(let host): return "Can't resolve \u{201C}\(host)\u{201D}"
            case .rpc(let code, let m): return "\(m) (\(code))"
            case .socket(let why):      return why
            }
        }
    }

    static let defaultPort: UInt16 = 30000
    /// The firmware drops requests that arrive this soon after a reply.
    static let quietWindow: TimeInterval = 2.0
    /// When each copy of a request goes out, relative to the first.
    static let resendAt: [TimeInterval] = [0, 0.5, 2.5, 5.0]
    /// How long to listen after the last copy.
    static let lastWait: TimeInterval = 2.5

    private var fd: Int32 = -1
    private var nextID: UInt16 = 1
    private var lastReply = Date.distantPast

    deinit { if fd >= 0 { close(fd) } }

    // MARK: - Calls

    /// One request, one reply. Returns the `result` object.
    func call(_ method: String, params: [String: Any] = ["id": 0],
              host: String, port: UInt16 = defaultPort) -> Result<[String: Any], Failure> {
        guard let address = Self.resolve(host, port: port) else { return .failure(.badAddress(host)) }
        if case .failure(let failure) = openSocket() { return .failure(failure) }

        let wait = lastReply.addingTimeInterval(Self.quietWindow).timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }

        // The firmware keeps the id as uint16; 0 is what it answers parse errors with.
        let id = Int(nextID)
        nextID = nextID == .max ? 1 : nextID + 1
        let request: [String: Any] = ["id": id, "method": method, "params": params]
        guard let payload = try? JSONSerialization.data(withJSONObject: request) else {
            return .failure(.socket("Can't encode \(method)"))
        }

        let start = Date()
        for (index, offset) in Self.resendAt.enumerated() {
            let sendAt = start.addingTimeInterval(offset)
            if sendAt > Date() { Thread.sleep(until: sendAt) }
            if let failure = send(payload, to: address) { return .failure(failure) }

            let until = index + 1 < Self.resendAt.count
                ? start.addingTimeInterval(Self.resendAt[index + 1])
                : Date().addingTimeInterval(Self.lastWait)
            while let reply = receive(until: until) {
                guard reply["id"] as? Int == id else { continue }   // a stale answer
                lastReply = Date()
                if let result = reply["result"] as? [String: Any] { return .success(result) }
                let error = reply["error"] as? [String: Any]
                return .failure(.rpc(code: error?["code"] as? Int ?? 0,
                                     message: error?["message"] as? String ?? "Error reply"))
            }
        }
        return .failure(.noReply)
    }

    /// Asks every station on the local networks to introduce itself.
    ///
    /// Sent as a directed broadcast on each physical interface rather than to
    /// 255.255.255.255: with WireGuard up the default route is a `utun`, and
    /// the limited broadcast would leave through the tunnel.
    func discover(timeout: TimeInterval = 8) -> [Station] {
        if case .failure = openSocket() { return [] }
        let wait = lastReply.addingTimeInterval(Self.quietWindow).timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }

        let id = Int(nextID)
        nextID = nextID == .max ? 1 : nextID + 1
        let request: [String: Any] = ["id": id, "method": "Marstek.GetDevice", "params": ["ble_mac": "0"]]
        guard let payload = try? JSONSerialization.data(withJSONObject: request) else { return [] }

        // Resent like a call: the quiet window is the station's, not ours, so
        // a broadcast right after another client's reply is dropped. Measured
        // 2026-10-14 over Wi-Fi: alone, 4 of 6 answered the first copy and 2
        // the 0.5 s one; right after a five-call poll only the 2.5 s copy was
        // answered, close to 5 s — hence the long default.
        let targets = Self.broadcastAddresses()
        var found: [Station] = []
        let start = Date()
        for (index, offset) in Self.resendAt.enumerated() where offset < timeout {
            let sendAt = start.addingTimeInterval(offset)
            if sendAt > Date() { Thread.sleep(until: sendAt) }
            for target in targets { _ = send(payload, to: target) }

            let next = index + 1 < Self.resendAt.count ? Self.resendAt[index + 1] : .infinity
            let until = start.addingTimeInterval(min(next, timeout))
            while let reply = receive(until: until) {
                // Our own broadcast loops back; only a device fills `result`.
                guard reply["id"] as? Int == id,
                      let result = reply["result"] as? [String: Any],
                      let station = Station(result) else { continue }
                lastReply = Date()
                if !found.contains(station) { found.append(station) }
            }
            // Everyone on the network answers the same round.
            if !found.isEmpty { break }
        }
        return found
    }

    /// Who answered a discovery broadcast.
    struct Station: Equatable {
        let device: String
        let ip: String
        let bleMac: String

        init?(_ result: [String: Any]) {
            guard let ip = result["ip"] as? String, !ip.isEmpty else { return nil }
            self.ip = ip
            self.device = result["device"] as? String ?? "Marstek"
            self.bleMac = result["ble_mac"] as? String ?? ""
        }
    }

    // MARK: - Socket

    private func openSocket() -> Result<Void, Failure> {
        if fd >= 0 { return .success(()) }
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { return .failure(.socket("socket(): \(Self.errnoText())")) }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let why = Self.errnoText()
            close(s)
            return .failure(.socket("bind(): \(why)"))
        }
        fd = s
        return .success(())
    }

    private func send(_ payload: Data, to address: sockaddr_in) -> Failure? {
        var target = address
        let sent = payload.withUnsafeBytes { bytes in
            withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent < 0 else { return nil }
        let code = errno
        // Local Network privacy refuses the send itself, with "No route to host".
        if code == EHOSTUNREACH || code == EPERM {
            return .blocked("macOS blocked the request (\(Self.errnoText(code)))")
        }
        return .socket("sendto(): \(Self.errnoText(code))")
    }

    /// The next parsed datagram before `until`, or nil when time is up.
    private func receive(until: Date) -> [String: Any]? {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let left = until.timeIntervalSinceNow
            guard left > 0 else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(left * 1000) + 1)
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return nil }
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { continue }
            if let json = try? JSONSerialization.jsonObject(with: Data(buffer[0..<n])) as? [String: Any] {
                return json
            }
        }
    }

    // MARK: - Addresses

    private static func resolve(_ host: String, port: UInt16) -> sockaddr_in? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        if inet_pton(AF_INET, host, &address.sin_addr) == 1 { return address }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return nil }
        defer { freeaddrinfo(list) }
        guard let sa = first.pointee.ai_addr else { return nil }
        sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { address.sin_addr = $0.pointee.sin_addr }
        return address
    }

    /// The broadcast address of every IPv4 interface that is up, can
    /// broadcast and is not a tunnel or loopback.
    private static func broadcastAddresses() -> [sockaddr_in] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }

        var result: [sockaddr_in] = []
        var cursor = list
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let broadcast = entry.ifa_dstaddr else { continue }
            var target = broadcast.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            target.sin_port = defaultPort.bigEndian
            if !result.contains(where: { $0.sin_addr.s_addr == target.sin_addr.s_addr }) {
                result.append(target)
            }
        }
        return result
    }

    private static func errnoText(_ code: Int32 = errno) -> String {
        String(cString: strerror(code))
    }
}
