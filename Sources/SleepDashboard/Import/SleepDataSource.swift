import Foundation

protocol SleepDataSource: Sendable {
	func parse(fileURL: URL) -> SleepRecordStream
}

protocol CSVChunkSource: Sendable {
	func open(fileURL: URL) throws -> any CSVChunkReader
}

protocol CSVChunkReader: Sendable {
	func readChunk() async throws -> Data?
	func close() async
}

struct FileCSVChunkSource: CSVChunkSource {
	let chunkSize: Int

	init(chunkSize: Int = 64 * 1_024) {
		self.chunkSize = chunkSize
	}

	func open(fileURL: URL) throws -> any CSVChunkReader {
		try FileCSVChunkReader(fileURL: fileURL, chunkSize: chunkSize)
	}
}

private actor FileCSVChunkReader: CSVChunkReader {
	private let file_handle: FileHandle
	private let chunk_size: Int
	private var is_closed = false

	init(fileURL: URL, chunkSize: Int) throws {
		self.file_handle = try FileHandle(forReadingFrom: fileURL)
		self.chunk_size = chunkSize
	}

	func readChunk() async throws -> Data? {
		try Task.checkCancellation()
		guard !is_closed else {
			return nil
		}

		let data = try file_handle.read(upToCount: chunk_size)
		guard let data, !data.isEmpty else {
			return nil
		}

		return data
	}

	func close() async {
		guard !is_closed else {
			return
		}

		is_closed = true
		try? file_handle.close()
	}
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
