import Foundation

struct TimeVerificationResult {
    var deviceTime: Date
    var verifiedTime: Date
    var differenceSeconds: TimeInterval
    var source: String
}

enum TimeVerificationError: LocalizedError {
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Сервис времени вернул некорректный ответ."
        case .unavailable: return "Не удалось получить проверенное время. Проверьте подключение к интернету и повторите попытку."
        }
    }
}

struct TimeVerificationService {
    func verify() async throws -> TimeVerificationResult {
        if let cloudflare = try? await cloudflareTime() {
            let device = Date()
            return TimeVerificationResult(
                deviceTime: device,
                verifiedTime: cloudflare,
                differenceSeconds: device.timeIntervalSince(cloudflare),
                source: "Cloudflare HTTPS"
            )
        }

        if let apple = try? await appleHeaderTime() {
            let device = Date()
            return TimeVerificationResult(
                deviceTime: device,
                verifiedTime: apple,
                differenceSeconds: device.timeIntervalSince(apple),
                source: "Apple HTTPS"
            )
        }
        throw TimeVerificationError.unavailable
    }

    private func cloudflareTime() async throws -> Date {
        guard let url = URL(string: "https://www.cloudflare.com/cdn-cgi/trace") else {
            throw TimeVerificationError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let body = String(data: data, encoding: .utf8) else {
            throw TimeVerificationError.invalidResponse
        }
        guard let line = body.split(separator: "\n").first(where: { $0.hasPrefix("ts=") }),
              let seconds = TimeInterval(line.dropFirst(3)) else {
            throw TimeVerificationError.invalidResponse
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private func appleHeaderTime() async throws -> Date {
        guard let url = URL(string: "https://www.apple.com/") else {
            throw TimeVerificationError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let dateHeader = http.value(forHTTPHeaderField: "Date") else {
            throw TimeVerificationError.invalidResponse
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        guard let date = formatter.date(from: dateHeader) else {
            throw TimeVerificationError.invalidResponse
        }
        return date
    }
}
