//
//  GroqJudge.swift
//  SwiftMem — AI Judge for test suite results
//
//  Free-tier limits for llama-3.3-70b-versatile (as of March 2026):
//    RPM  30   — requests per minute
//    RPD  1,000 — requests per day
//    TPM  12,000 — tokens per minute
//    TPD  100,000 — tokens per day
//
//  Our test judge makes exactly ONE call (~800 tokens), so daily limits are
//  never a concern in practice. The retry logic below guards against the
//  rare case where you're also hammering the API from somewhere else.
//

import Foundation

// MARK: - GroqJudge

actor GroqJudge {

    // ── Configuration ────────────────────────────────────────────────────────

    var apiKey: String = ""

    /// llama-3.3-70b-versatile: 30 RPM / 12k TPM — smart enough for evaluation
    /// llama3-8b-8192: 30 RPM / 30k TPM — faster, higher token allowance
    var model: String = "llama-3.3-70b-versatile"

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    /// Per-minute retry ceiling. Above this we assume a daily limit was hit and bail.
    private let dailyLimitThreshold: Double = 3600   // 1 hour → must be daily quota

    /// Max retries for per-minute 429s (wait is short, worth retrying)
    private let maxPerMinuteRetries = 3

    // ── Public ────────────────────────────────────────────────────────────────

    func setAPIKey(_ key: String) { apiKey = key }

    /// Evaluate test results. Returns nil if key is missing or all retries fail.
    func judge(results: [TestResult], summary: String) async -> String? {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("⚠️ [GroqJudge] No API key — skipping AI evaluation")
            return nil
        }

        let prompt = buildPrompt(results: results, summary: summary)
        print("🤖 [GroqJudge] Sending \(results.count) test results to \(model)…")

        var perMinuteAttempts = 0

        while true {
            switch await callGroq(prompt: prompt) {

            case .success(let verdict, let quota):
                logQuota(quota)
                return verdict

            case .rateLimited(let retryAfter, let quota):
                logQuota(quota)

                if retryAfter >= dailyLimitThreshold {
                    // Daily/total quota exhausted — no point retrying today
                    print("🚫 [GroqJudge] Daily quota hit (retry-after \(Int(retryAfter))s). Skipping AI judge.")
                    return nil
                }

                perMinuteAttempts += 1
                if perMinuteAttempts > maxPerMinuteRetries {
                    print("⚠️ [GroqJudge] Per-minute limit hit \(maxPerMinuteRetries)× — giving up.")
                    return nil
                }

                // Per-minute limit: wait for retry-after (or a safe default)
                let wait = max(retryAfter, 5.0)
                print("⏳ [GroqJudge] Rate limited (RPM/TPM). Waiting \(Int(wait))s… (attempt \(perMinuteAttempts)/\(maxPerMinuteRetries))")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))

            case .failure(let msg):
                print("⚠️ [GroqJudge] Request failed: \(msg)")
                return nil
            }
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private struct Quota {
        var remainingRequests: Int?  // x-ratelimit-remaining-requests  (RPM bucket)
        var remainingTokens: Int?    // x-ratelimit-remaining-tokens    (TPM bucket)
        var resetRequests: String?   // x-ratelimit-reset-requests      (RPD reset time)
        var resetTokens: String?     // x-ratelimit-reset-tokens        (TPM reset time)
    }

    private enum CallResult {
        case success(String, Quota)
        case rateLimited(retryAfter: Double, Quota)
        case failure(String)
    }

    private func callGroq(prompt: String) async -> CallResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": prompt]
            ],
            "max_tokens": 512,
            "temperature": 0.2
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure("JSON serialization error")
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as! HTTPURLResponse
            let quota = parseQuota(from: http)

            if http.statusCode == 429 {
                // retry-after is the authoritative wait time from Groq
                let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                    .flatMap { Double($0) } ?? 60.0
                return .rateLimited(retryAfter: retryAfter, quota)
            }

            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                return .failure("HTTP \(http.statusCode): \(body.prefix(300))")
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                return .failure("Unexpected response shape")
            }

            return .success(content.trimmingCharacters(in: .whitespacesAndNewlines), quota)

        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func parseQuota(from http: HTTPURLResponse) -> Quota {
        Quota(
            remainingRequests: http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests").flatMap(Int.init),
            remainingTokens:   http.value(forHTTPHeaderField: "x-ratelimit-remaining-tokens").flatMap(Int.init),
            resetRequests:     http.value(forHTTPHeaderField: "x-ratelimit-reset-requests"),
            resetTokens:       http.value(forHTTPHeaderField: "x-ratelimit-reset-tokens")
        )
    }

    private func logQuota(_ quota: Quota) {
        var parts: [String] = []
        if let r = quota.remainingRequests { parts.append("requests left: \(r)/30 RPM") }
        if let t = quota.remainingTokens   { parts.append("tokens left: \(t)/12000 TPM") }
        if let rr = quota.resetRequests    { parts.append("RPD resets: \(rr)") }
        if !parts.isEmpty {
            print("📊 [GroqJudge] Quota — \(parts.joined(separator: " · "))")
        }
    }

    // ── Prompt builders ───────────────────────────────────────────────────────

    private let systemPrompt = """
    You are an expert evaluator for SwiftMem, an on-device graph-based memory system for iOS.
    You receive automated test results and write a concise technical verdict.
    Be direct. Flag real issues. Acknowledge what works. Keep it under 200 words.
    """

    private func buildPrompt(results: [TestResult], summary: String) -> String {
        let lines = results.map { r -> String in
            let tag = r.status == .pass ? "PASS" :
                      r.status == .fail ? "FAIL" :
                      r.status == .warn ? "WARN" : "SKIP"
            return "[\(tag)] \(r.name) (\(Int(r.duration))ms): \(r.detail)"
        }.joined(separator: "\n")

        return """
        SwiftMem test run — \(summary)

        \(lines)

        Evaluate:
        1. Are the failures/warnings significant or acceptable?
        2. Is the core memory pipeline (add, embed, search, RRF) healthy?
        3. Any patterns in what's failing that suggest a systemic issue?
        4. Overall verdict: production-ready for on-device use?
        """
    }
}
