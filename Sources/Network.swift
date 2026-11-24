import Darwin
import Foundation

enum InterfaceTraffic {
    static func read(_ interface: String) -> Traffic? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }

        // NET_RT_IFLIST2 provides 64-bit counters, including on busy connections.
        var query = [CTL_NET, PF_ROUTE, 0, AF_UNSPEC, NET_RT_IFLIST2, Int32(index)]
        var size = 0
        guard sysctl(&query, u_int(query.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var response = Data(count: size)
        let result = response.withUnsafeMutableBytes {
            sysctl(&query, u_int(query.count), $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }

        return response.withUnsafeBytes { bytes -> Traffic? in
            var offset = 0
            while offset + 4 <= size {
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { return nil }
                if bytes[offset + 2] == UInt8(RTM_VERSION),
                   bytes[offset + 3] == UInt8(RTM_IFINFO2),
                   length >= MemoryLayout<if_msghdr2>.size {
                    let info = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if UInt32(info.ifm_index) == index {
                        return Traffic(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
                    }
                }
                offset += length
            }
            return nil
        }
    }
}
