import Foundation

struct JevCategorization: Equatable, Sendable {
    let laneID: UUID?
    let confidence: Double
    let probabilities: [String: Double]
    let model: String
}

enum JevClientError: Error, Equatable {
    case missingToken
    case emptyThought
    case noLanes
    case invalidResponse
    case unexpectedHTTPStatus(Int)
}

private struct JevChoiceQuestion: Encodable {
    let type = "choice"
    let instructions: String
    let criteria: [String: String]
}

private struct JevRequest: Encodable {
    let state: String
    let model: String
    let questions: [String: JevChoiceQuestion]
}

private struct JevChoiceAnswer: Decodable {
    let type: String
    let choice: String
    let probabilities: [String: Double]
    let confidence: Double
}

private struct JevResponse: Decodable {
    let model: String
    let answers: [String: JevChoiceAnswer]
}

/// Thin HTTP client for Jev's System One Choice evaluation.
///
/// The API token is loaded from SecureTokenStore and is never accepted as a
/// request argument, logged, or included in an error message.
final class JevClient: @unchecked Sendable {
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let model = "jev-latest"
    static let laneQuestionID = "lane"
    static let noMatchOption = "__unassigned__"
    static let autoCategorizationConfidenceThreshold = 0.91

    private let tokenStore: SecureTokenStore
    private let session: URLSession

    init(tokenStore: SecureTokenStore = .shared, session: URLSession = .shared) {
        self.tokenStore = tokenStore
        self.session = session
    }

    @MainActor
    func autoCategorize(thought: String, lanes: [Lane]) async throws -> JevCategorization {
        let trimmedThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedThought.isEmpty else { throw JevClientError.emptyThought }
        guard !lanes.isEmpty else { throw JevClientError.noLanes }
        guard let token = try tokenStore.token(forKey: SecureTokenKeys.jev), !token.isEmpty else {
            throw JevClientError.missingToken
        }

        let criteria = Self.criteria(for: lanes)
        let requestBody = JevRequest(
            state: trimmedThought,
            model: Self.model,
            questions: [
                Self.laneQuestionID: JevChoiceQuestion(
                    instructions: "Which lane best fits this thought? Choose __unassigned__ when no lane is a clear fit.",
                    criteria: criteria
                )
            ]
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JevClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw JevClientError.unexpectedHTTPStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(JevResponse.self, from: data)
        guard let answer = decoded.answers[Self.laneQuestionID], answer.type == "choice" else {
            throw JevClientError.invalidResponse
        }

        let laneIDs = Set(lanes.map { $0.id.uuidString })
        let laneID = answer.choice == Self.noMatchOption
            ? nil
            : UUID(uuidString: answer.choice).flatMap { laneIDs.contains($0.uuidString) ? $0 : nil }
        guard answer.choice == Self.noMatchOption || laneID != nil else {
            throw JevClientError.invalidResponse
        }

        return JevCategorization(
            laneID: laneID,
            confidence: answer.confidence,
            probabilities: answer.probabilities,
            model: decoded.model
        )
    }

    static func criteria(for lanes: [Lane]) -> [String: String] {
        var criteria = Dictionary(uniqueKeysWithValues: lanes.map { lane in
            let description = lane.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let purpose = description?.isEmpty == false ? description! : "No description provided. Use the lane name as the guide."
            return (lane.id.uuidString, "\(lane.name): \(purpose)")
        })
        criteria[noMatchOption] = "The thought does not clearly belong in any listed lane; leave it unassigned."
        return criteria
    }
}
