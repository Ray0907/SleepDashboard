import Foundation

protocol SleepDataSource: Sendable {
	func parse(fileURL: URL) -> SleepRecordStream
}

struct SleepParseSummary: Sendable, Equatable {
	let parsedCount: Int
	let skippedRows: [SleepSkippedRow]

	var skippedCount: Int {
		skippedRows.count
	}
}

struct SleepSkippedRow: Sendable, Equatable {
	let rowNumber: Int
	let reason: String
}

struct SleepRecordStream: AsyncSequence, Sendable {
	typealias Element = ParsedSleepRecord
	typealias AsyncIterator = AsyncThrowingStream<Element, Error>.Iterator

	private let records: AsyncThrowingStream<Element, Error>
	private let summary_task: Task<SleepParseSummary, Error>

	init(
		records: AsyncThrowingStream<Element, Error>,
		summaryTask: Task<SleepParseSummary, Error>
	) {
		self.records = records
		self.summary_task = summaryTask
	}

	func makeAsyncIterator() -> AsyncIterator {
		records.makeAsyncIterator()
	}

	func summary() async throws -> SleepParseSummary {
		try await summary_task.value
	}
}

enum AutoSleepCSVImportError: LocalizedError, Sendable {
	case unreadableFile(String)
	case invalidUTF8
	case emptyFile
	case invalidHeader(String)
	case missingRequiredColumns([String])

	var errorDescription: String? {
		switch self {
		case .unreadableFile(let file_name):
			return "Could not read \(file_name). Check that the file is accessible."
		case .invalidUTF8:
			return "The AutoSleep CSV is not valid UTF-8 text."
		case .emptyFile:
			return "The AutoSleep CSV is empty."
		case .invalidHeader(let reason):
			return "The AutoSleep CSV header is malformed: \(reason)"
		case .missingRequiredColumns(let columns):
			return "The AutoSleep CSV is missing required columns: "
				+ columns.joined(separator: ", ") + "."
		}
	}
}
