import Foundation

public enum MeetingCaptureState: String, Codable, Sendable {
    case idle, preparing, recording, paused, processing, completed, failed, permissionRequired, unavailable
}

public enum MeetingSourceType: String, Codable, Sendable {
    case onlineMeeting, physicalMeeting, mixed, unknown
}

public enum ActionItemStatus: String, Codable, Sendable {
    case proposed, assigned, needsConfirmation, unclear
}

public struct TranscriptSegment: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var speakerID: String?
    public var languageCode: String?
    public var confidence: Double?

    public init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String,
                speakerID: String? = nil, languageCode: String? = nil, confidence: Double? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speakerID = speakerID
        self.languageCode = languageCode
        self.confidence = confidence
    }
}

public struct MeetingMetadata: Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var durationSeconds: TimeInterval
    public var title: String
    public var audience: String
    public var detectedLanguages: [String]
    public var participantCountEstimate: Int?
    public var sourceType: MeetingSourceType

    public init(id: UUID = UUID(), startedAt: Date = .now, endedAt: Date? = nil,
                durationSeconds: TimeInterval = 0, title: String = "", audience: String = "",
                detectedLanguages: [String] = [], participantCountEstimate: Int? = nil,
                sourceType: MeetingSourceType = .unknown) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.title = title
        self.audience = audience
        self.detectedLanguages = detectedLanguages
        self.participantCountEstimate = participantCountEstimate
        self.sourceType = sourceType
    }

    public var noteTitle: String {
        let agenda = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        let timestamp = formatter.string(from: startedAt)
        return "\(agenda.isEmpty ? "Meeting" : agenda) — \(timestamp)"
    }
}

public struct DiscussionSection: Codable, Sendable {
    public var topic: String
    public var summary: String
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    public var speakers: [String]
}

public struct DiscussionPoint: Codable, Sendable {
    public var text: String
    public var topic: String?
    public var sourceStartTime: TimeInterval?
}

public struct DecisionItem: Codable, Sendable {
    public var decision: String
    public var rationale: String?
    public var owner: String?
    public var sourceStartTime: TimeInterval?
    public var confidence: Double?
}

public struct ActionItem: Codable, Sendable {
    public var task: String
    public var owner: String?
    public var deadline: String?
    public var status: ActionItemStatus
    public var sourceStartTime: TimeInterval?
    public var confidence: Double?
}

public struct RiskItem: Codable, Sendable {
    public var risk: String
    public var impact: String?
    public var mitigation: String?
    public var owner: String?
    public var sourceStartTime: TimeInterval?
}

public struct OpenQuestion: Codable, Sendable {
    public var question: String
    public var owner: String?
    public var sourceStartTime: TimeInterval?
}

public struct TopicTimelineItem: Codable, Sendable {
    public var topic: String
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    public var summary: String
}

public struct MeetingIntelligenceResult: Codable, Sendable {
    public var title: String
    public var executiveSummary: String
    public var detailedNotes: [DiscussionSection]
    public var discussionPoints: [DiscussionPoint]
    public var decisions: [DecisionItem]
    public var actionItems: [ActionItem]
    public var risks: [RiskItem]
    public var openQuestions: [OpenQuestion]
    public var followUpEmail: String
    public var topicTimeline: [TopicTimelineItem]
    public var transcript: [TranscriptSegment]
    public var generatedAt: Date
    public var modelProvider: String
    public var language: String?

    public init(title: String, executiveSummary: String, detailedNotes: [DiscussionSection] = [],
                discussionPoints: [DiscussionPoint] = [], decisions: [DecisionItem] = [],
                actionItems: [ActionItem] = [], risks: [RiskItem] = [], openQuestions: [OpenQuestion] = [],
                followUpEmail: String = "", topicTimeline: [TopicTimelineItem] = [],
                transcript: [TranscriptSegment] = [], generatedAt: Date = .now,
                modelProvider: String, language: String? = nil) {
        self.title = title
        self.executiveSummary = executiveSummary
        self.detailedNotes = detailedNotes
        self.discussionPoints = discussionPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.risks = risks
        self.openQuestions = openQuestions
        self.followUpEmail = followUpEmail
        self.topicTimeline = topicTimeline
        self.transcript = transcript
        self.generatedAt = generatedAt
        self.modelProvider = modelProvider
        self.language = language
    }
}

public enum MeetingMarkdownRenderer {
    public static func renderTranscript(metadata: MeetingMetadata, transcript: String) -> String {
        ["# \(metadata.noteTitle)", "",
         "**Agenda:** \(metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not specified" : metadata.title)",
         "**Date:** \(metadata.startedAt.formatted(date: .long, time: .shortened))",
         "**Duration:** \(duration(metadata.durationSeconds))", "",
         "## Transcript", "", transcript.trimmingCharacters(in: .whitespacesAndNewlines), ""]
            .joined(separator: "\n")
    }

    public static func render(metadata: MeetingMetadata, result: MeetingIntelligenceResult,
                              includeTranscript: Bool = true) -> String {
        var lines = ["# \(result.title.isEmpty ? metadata.noteTitle : result.title)", "",
                     "**Agenda:** \(metadata.title.isEmpty ? "Not specified" : metadata.title)",
                     "**Date:** \(metadata.startedAt.formatted(date: .long, time: .shortened))",
                     "**Duration:** \(duration(metadata.durationSeconds))"]
        if !metadata.audience.isEmpty { lines.append("**Audience:** \(metadata.audience)") }
        if !metadata.detectedLanguages.isEmpty { lines.append("**Languages:** \(metadata.detectedLanguages.joined(separator: ", "))") }
        if !result.executiveSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines += ["", "## Executive Summary", "", result.executiveSummary]
        }

        appendSection("Detailed Notes", values: result.detailedNotes.map { "### \($0.topic)\n\n\($0.summary)" }, to: &lines)
        appendSection("Discussion Points", values: result.discussionPoints.map { "- \($0.text)" }, to: &lines)
        appendSection("Decisions", values: result.decisions.map { decision in
            "- \(decision.decision)" + (decision.owner.map { " (Owner: \($0))" } ?? "")
        }, to: &lines)
        appendSection("Action Items", values: result.actionItems.map { item in
            "- [ ] \(item.task) — Owner: \(item.owner ?? "Not specified"); Deadline: \(item.deadline ?? "Not specified"); Status: \(item.status.rawValue)"
        }, to: &lines)
        appendSection("Risks and Blockers", values: result.risks.map { "- \($0.risk)" }, to: &lines)
        appendSection("Open Questions", values: result.openQuestions.map { "- \($0.question)" }, to: &lines)
        appendSection("Topic Timeline", values: result.topicTimeline.map {
            "- \(clock($0.startTime))–\(clock($0.endTime)) — \($0.topic): \($0.summary)"
        }, to: &lines)
        if !result.followUpEmail.isEmpty { lines += ["", "## Follow-up Email", "", result.followUpEmail] }
        if includeTranscript, !result.transcript.isEmpty {
            lines += ["", "## Transcript", ""]
            lines += result.transcript.map { "[\(clock($0.startTime))] \($0.speakerID.map { "\($0): " } ?? "")\($0.text)" }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func appendSection(_ title: String, values: [String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines += ["", "## \(title)", ""] + values
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(total % 60)s"
    }

    private static func clock(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "--:--" }
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
