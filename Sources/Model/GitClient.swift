import Foundation

/// Errors from GitClient operations. All are safe to show to the user at a high level.
enum GitError: Error, LocalizedError {
    case gitNotFound
    case notARepository(URL)
    case fileNotTracked(URL)
    case commandFailed(exitCode: Int32, stderr: String)
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git is not available (git not found in PATH)."
        case .notARepository(let url):
            return "Not a git repository (or parent): \(url.lastPathComponent)"
        case .fileNotTracked(let url):
            return "File is not tracked by git: \(url.lastPathComponent)"
        case .commandFailed(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Git command failed (exit \(code)): \(detail)"
        case .unexpectedOutput(let detail):
            return "Unexpected output from git: \(detail)"
        }
    }
}

/// Lightweight description of one point in a file's git history.
/// The special "working tree" revision is represented by the caller using the live
/// on-disk content (no sha); history lists may include a synthetic entry for it.
struct GitVersion: Equatable, Hashable {
    /// Full commit SHA, or empty for the working-tree sentinel.
    let sha: String
    /// Short SHA for display (first 7-8 chars or the empty sentinel marker).
    let shortSha: String
    /// First line of the commit subject.
    let subject: String
    /// Author date as an ISO-ish string (or "Working tree" for the live version).
    let dateString: String

    /// True for the synthetic "current on-disk / working tree" entry.
    var isWorkingTree: Bool { sha.isEmpty }

    static let workingTree = GitVersion(
        sha: "",
        shortSha: "WT",
        subject: "Working tree (current on disk)",
        dateString: "Now"
    )
}

/// Small client for the git operations we need for document history.
/// All git interaction goes through /usr/bin/env git (or equivalent) using Process.
/// Safe argument arrays are used; never constructs a shell command string.
///
/// The client is intentionally small and isolated so it can later be replaced
/// by a libgit2-backed implementation without touching callers.
@MainActor
final class GitClient {

    // MARK: - Public API (per document file URL)

    /// Returns (toplevel, relativePathUnderRepo) for the given file if it is inside
    /// a git work tree and the file is tracked (or at least the dir is a repo).
    /// Throws GitError.gitNotFound or .notARepository on failure to discover.
    func repoContext(for file: URL) async throws -> (toplevel: URL, relPath: String) {
        let toplevel = try await runForToplevel(containing: file)
        let rel = try await runForRelativePath(file: file, in: toplevel)
        // Best-effort tracked check (ls-files will return empty for untracked).
        // We still allow the context for "show history" which can surface untracked nicely.
        return (toplevel, rel)
    }

    /// Returns a bounded list of versions for the file (newest first), plus a
    /// leading WorkingTree sentinel so UIs can treat "current" uniformly.
    /// `limit` is a soft cap (git -n). Includes "load more" signal via caller logic.
    func history(for file: URL, limit: Int = 100) async throws -> [GitVersion] {
        let (toplevel, rel) = try await repoContext(for: file)

        // Always offer the working tree as the first choice.
        var result: [GitVersion] = [.workingTree]

        let args = [
            "git", "-C", toplevel.path,
            "log", "--follow", "--oneline", "-n", String(limit),
            "--", rel
        ]
        let (stdout, stderr, code) = try await runProcess(arguments: args)
        if code != 0 {
            // If the file simply has no commits yet (newly added, never committed),
            // git log exits 0 with empty output. Non-zero usually means other trouble.
            if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GitError.commandFailed(exitCode: code, stderr: stderr)
            }
        }

        let lines = stdout.split(whereSeparator: \.isNewline)
        for line in lines {
            // Format: "<sha1> <subject...>"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let space = trimmed.firstIndex(of: " ") {
                let sha = String(trimmed[..<space])
                let subject = String(trimmed[trimmed.index(after: space)...])
                let short = String(sha.prefix(8))
                // For the list we only need subject + short sha; date can be added
                // later with a separate pretty format if wanted.
                result.append(GitVersion(sha: sha, shortSha: short, subject: subject, dateString: ""))
            }
        }

        // If we got nothing beyond the sentinel, the path may be untracked or have
        // no history. We still return the sentinel so the UI can say "only current".
        return result
    }

    /// Returns the exact text content of the file at the given revision (blob).
    /// For the working tree sentinel, the caller should just use the live document text.
    /// `rev` may be a full sha, short sha, HEAD, HEAD~3, a tag, etc.
    func content(at rev: String, for file: URL) async throws -> String {
        if rev.isEmpty {
            // Working tree sentinel: let caller use live on-disk content.
            throw GitError.unexpectedOutput("content() called for working-tree sentinel")
        }
        let (toplevel, rel) = try await repoContext(for: file)
        // git show <rev>:<rel> emits the exact committed blob (no working-tree mods).
        let args = ["git", "-C", toplevel.path, "show", "\(rev):\(rel)"]
        let (stdout, stderr, code) = try await runProcess(arguments: args)
        if code != 0 {
            if stderr.lowercased().contains("exists on disk") || stderr.lowercased().contains("does not exist") {
                throw GitError.fileNotTracked(file)
            }
            throw GitError.commandFailed(exitCode: code, stderr: stderr)
        }
        return stdout
    }

    /// Returns the full commit message (subject + body) for a revision.
    /// For the empty rev (working tree) returns a placeholder.
    func commitMessage(for rev: String, file: URL) async throws -> String {
        if rev.isEmpty {
            return "Live (working tree)"
        }
        let (toplevel, _) = try await repoContext(for: file)
        // -s suppresses the diff, %B is full raw message (subject + body)
        let args = ["git", "-C", toplevel.path, "show", "-s", "--format=%B", rev]
        let (stdout, stderr, code) = try await runProcess(arguments: args)
        if code != 0 {
            throw GitError.commandFailed(exitCode: code, stderr: stderr)
        }
        let msg = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "(no commit message)" : msg
    }

    // MARK: - Low-level process helpers (internal for now)

    private func runForToplevel(containing file: URL) async throws -> URL {
        // Start the search from the file's directory (handles files inside subdirs).
        let startDir = file.deletingLastPathComponent()
        let args = ["git", "-C", startDir.path, "rev-parse", "--show-toplevel"]
        let (stdout, stderr, code) = try await runProcess(arguments: args)
        if code != 0 {
            if stderr.lowercased().contains("not a git repository") ||
               stderr.lowercased().contains("not a git repo") {
                throw GitError.notARepository(startDir)
            }
            // Could be "git not found".
            if stderr.lowercased().contains("command not found") || stdout.isEmpty && code == 127 {
                throw GitError.gitNotFound
            }
            throw GitError.commandFailed(exitCode: code, stderr: stderr)
        }
        let path = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw GitError.notARepository(startDir) }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func runForRelativePath(file: URL, in toplevel: URL) async throws -> String {
        // Use ls-files --full-name to get the repo-relative path (handles renames etc.).
        // If the file is untracked we still get a usable relative path for show/log on
        // historical commits that do contain it; for pure untracked we surface later.
        let args = [
            "git", "-C", toplevel.path,
            "ls-files", "--full-name", "--", file.path
        ]
        let (stdout, _, code) = try await runProcess(arguments: args)
        if code != 0 {
            // Non-fatal for our purposes; fall back to a manual relative computation.
        }
        let rel = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rel.isEmpty {
            return rel
        }
        // Fallback: compute relative path ourselves (best effort).
        let fileStd = file.standardizedFileURL
        let topStd = toplevel.standardizedFileURL
        if fileStd.path.hasPrefix(topStd.path) {
            let relPath = fileStd.path.dropFirst(topStd.path.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relPath.isEmpty { return String(relPath) }
        }
        throw GitError.fileNotTracked(file)
    }

    /// Runs `env git ...` (or equivalent) with the provided argument list.
    /// Returns (stdout, stderr, exitCode). Never throws on non-zero exit; caller decides.
    private func runProcess(arguments: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        // Prefer /usr/bin/env so we ride the user's PATH for git.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            // Common case: /usr/bin/env exists but "git" is not on PATH.
            if arguments.first == "git" {
                throw GitError.gitNotFound
            }
            throw error
        }

        // Read output on background to avoid blocking the caller thread.
        async let outData = Task.detached { outPipe.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }.value

        process.waitUntilExit()

        let stdoutData = await outData
        let stderrData = await errData

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }
}