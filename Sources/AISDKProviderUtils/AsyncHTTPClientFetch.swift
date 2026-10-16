import Foundation
import AsyncHTTPClient
import NIOCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Linux transport for the fetch seam: AsyncHTTPClient (SwiftNIO) —
// non-blocking event-loop I/O, no per-request threads. corelibs
// URLSession (libcurl) is thread-per-request, HTTP/1.1-only and has no
// streaming API, which caps concurrency and features; SwiftNIO is the
// production-grade stack. Apple platforms keep URLSession (native and
// streaming-capable there).

private let sharedNIOClient = HTTPClient(eventLoopGroupProvider: .singleton)

/// Fetch backed by AsyncHTTPClient. The response is delivered as a
/// byte-chunk stream (matching the URLSession streaming shape), so
/// streaming callers keep working if a Linux transport grows into one.
func asyncHTTPClientFetch() -> FetchFunction {
    { request in
        var httpRequest = HTTPClientRequest(url: request.url!.absoluteString)
        switch request.httpMethod?.uppercased() {
        case "POST": httpRequest.method = .POST
        case "PUT": httpRequest.method = .PUT
        case "DELETE": httpRequest.method = .DELETE
        case "HEAD": httpRequest.method = .HEAD
        default: httpRequest.method = .GET
        }
        for (field, value) in request.allHTTPHeaderFields ?? [:] {
            httpRequest.headers.add(name: field, value: value)
        }
        if let body = request.httpBody {
            httpRequest.body = .bytes(ByteBuffer(bytes: body))
        }

        let response = try await sharedNIOClient.execute(
            httpRequest, timeout: .seconds(Int64(PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL)))

        var headers: [String: String] = [:]
        for (name, value) in response.headers {
            headers[name.lowercased()] = value
        }
        let urlResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: Int(response.status.code),
            httpVersion: "HTTP/1.1",
            headerFields: headers)!

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    for try await buffer in response.body {
                        continuation.yield(Data(buffer: buffer))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return FetchResponse(
            body: .stream(stream),
            urlResponse: urlResponse)
    }
}
