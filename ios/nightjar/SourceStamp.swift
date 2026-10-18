import Foundation

/// Where this build came from, provably. A build
/// phase ("Stamp source commit", in the project)
/// writes the building clone's exact commit —
/// and how many uncommitted changes rode along —
/// into the app's Info.plist as it builds. The
/// About screen reads it back and can hold it
/// against the repository's current HEAD: the
/// operator can prove the binary on the phone
/// is the source on file, bit for bit, at any
/// moment — or see exactly how it differs.
enum SourceStamp {
    static var commit: String? {
        Bundle.main.infoDictionary?["NJSourceCommit"]
            as? String
    }

    static var shortCommit: String? {
        commit.map { String($0.prefix(10)) }
    }

    /// Files the building tree had changed but
    /// uncommitted; 0 means the build is the
    /// commit exactly.
    static var uncommittedChanges: Int {
        let raw = Bundle.main
            .infoDictionary?["NJSourceChanges"] as? String
        return Int(raw ?? "") ?? 0
    }

    static var buildStamp: String? {
        Bundle.main.infoDictionary?["NJBuildStamp"]
            as? String
    }

    /// The repository's current main HEAD,
    /// straight from GitHub.
    static func currentRemoteHead() async -> String? {
        guard let url = URL(string:
            "https://api.github.com/repos/"
            + "chasebryan/nightjar-hack/commits/main")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json",
                         forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession
                .shared.data(for: request),
              (response as? HTTPURLResponse)?
                .statusCode == 200,
              let root = try? JSONSerialization
                .jsonObject(with: data)
                as? [String: Any],
              let sha = root["sha"] as? String
        else { return nil }
        return sha
    }

    /// The verdict, in one terse line.
    static func verdict(remoteHead: String) -> String {
        guard let mine = commit, mine != "unknown"
        else {
            return "This build carries no source "
                + "stamp — it was not built from a "
                + "git checkout."
        }
        if mine != remoteHead {
            return "The source has moved on. This "
                + "build is \(String(mine.prefix(10))); "
                + "current is "
                + "\(String(remoteHead.prefix(10)))."
        }
        if uncommittedChanges > 0 {
            return "The commit matches — but the "
                + "build carried "
                + "\(uncommittedChanges) uncommitted "
                + "change(s) on top of it."
        }
        return "Matches the current source — "
            + "bit for bit."
    }
}
