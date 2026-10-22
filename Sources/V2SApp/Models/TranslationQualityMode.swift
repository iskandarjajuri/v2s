import Foundation

/// How committed captions are translated. Apple Translation offers a low-latency and a
/// high-fidelity strategy; the first is ~10x faster, the second reads more naturally.
enum TranslationQualityMode: String, Codable, CaseIterable, Sendable {
    /// Show the fast translation at once, then swap in the natural one when it is ready.
    case progressive
    /// Previous behaviour: wait for the natural translation only.
    case naturalOnly
    /// Fast translation only; never replaced. Lowest latency, plainest wording.
    case fastOnly
}
