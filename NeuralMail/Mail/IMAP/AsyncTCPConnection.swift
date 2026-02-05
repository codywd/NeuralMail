import Foundation
import Network

actor AsyncTCPConnection {
    private let connection: NWConnection
    private var buffer = Data()

    init(host: String, port: Int, mode: NMSecurityMode) throws {
        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "NeuralMail", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port: \(port)"])
        }

        let parameters: NWParameters
        switch mode {
        case .tls:
            parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        case .starttls:
            parameters = NWParameters.tcp
        case .none:
            parameters = NWParameters.tcp
        }

        self.connection = NWConnection(host: endpointHost, port: endpointPort, using: parameters)
    }

    func connect() async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            connection.stateUpdateHandler = { state in
                guard !didResume else { return }
                switch state {
                case .ready:
                    didResume = true
                    connection.stateUpdateHandler = nil
                    continuation.resume(returning: ())
                case .failed(let error):
                    didResume = true
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    func cancel() {
        connection.cancel()
    }

    func write(_ string: String) async throws {
        try await write(Data(string.utf8))
    }

    func write(_ data: Data) async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func readExactly(_ count: Int) async throws -> Data {
        while buffer.count < count {
            let more = try await receiveMore()
            buffer.append(more)
        }
        let out = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(out)
    }

    func readLineCRLF() async throws -> Data {
        while true {
            if let range = buffer.range(of: Data([0x0D, 0x0A])) { // \r\n
                let line = buffer.prefix(upTo: range.lowerBound)
                buffer.removeSubrange(..<range.upperBound)
                return Data(line)
            }
            let more = try await receiveMore()
            buffer.append(more)
        }
    }

    private func receiveMore() async throws -> Data {
        let connection = self.connection
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: NSError(domain: "NeuralMail", code: 2, userInfo: [NSLocalizedDescriptionKey: "Connection closed by server."]))
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
        }
    }
}
