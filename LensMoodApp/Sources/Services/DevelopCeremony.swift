import Foundation

/// The develop ceremony's state — what the pipeline is doing to THIS
/// photograph, right now.
///
/// The honesty contract this type exists to keep:
///
/// * A step appears only once the stage it names has genuinely **begun**
///   (`begin`), so a label is never on screen while its stage is idle.
/// * A step is checked only once the **next** stage has begun — i.e. the work
///   it names actually returned.
/// * The final claim list is `Conductor.narration(for:)` (`settle`), which
///   states only what the pipeline truly did to this photograph. A live stage
///   that ran and found nothing (a subject pass on a scene with no faces)
///   therefore leaves no claim behind: the app looked, and says nothing.
/// * There is no percentage anywhere. `FilmEngine.develop` is one lazy Core
///   Image graph whose entire cost lands in a single `createCGImage`, so a
///   fraction would be an invention (see `ReadPhase`).
///
/// It is a plain value type with no clock, no timer and no task: it cannot
/// advance itself, which is precisely why it can never represent time that
/// nothing is spending.
struct DevelopCeremony: Equatable {
  /// the steps currently on screen, in the order they ran
  private(set) var steps: [String] = []
  /// index of the step running right now; every earlier step is complete.
  /// Equal to `steps.count` once everything has finished.
  private(set) var activeIndex: Int = 0
  /// true once the read returned and the list became narration's
  private(set) var isSettled = false

  private var reached: ReadPhase?

  init() {}

  /// The photograph itself is being fetched from the photo library
  /// (`PhotosPickerItem.loadTransferable`) — a real operation that genuinely
  /// takes time on an iCloud original, and the one thing running before the
  /// engine is handed anything at all. Named here because the alternative is
  /// what the panel used to do: claim "Reading the light" while nothing had
  /// been read yet.
  static let photoLoadStep = "Loading the photograph"

  static func loadingPhotograph() -> DevelopCeremony {
    var ceremony = DevelopCeremony()
    ceremony.steps = [photoLoadStep]
    ceremony.activeIndex = 0
    return ceremony
  }

  /// The live label for a read stage. Deliberately drawn from
  /// `Conductor.narration`'s own vocabulary so that when the read returns and
  /// the list settles to narration, the confirmed steps do not rename
  /// themselves under the user.
  static func label(for phase: ReadPhase) -> String {
    switch phase {
    case .metering: return "Reading the light"
    case .findingSubject: return "Finding your subject"
    case .tracingLight: return "Tracing the light sources"
    }
  }

  /// A read stage just began. Idempotent and order-independent: the list is
  /// rebuilt from the furthest stage reached, so a duplicated or reordered
  /// delivery (the callback is hopped from the read's thread to the main
  /// actor) converges on the same truthful picture and can never walk
  /// backwards.
  mutating func begin(_ phase: ReadPhase) {
    guard !isSettled else { return }
    if let reached, reached >= phase { return }
    reached = phase
    steps = ReadPhase.allCases.filter { $0 <= phase }.map(Self.label(for:))
    activeIndex = steps.count - 1
  }

  /// The read returned. The list becomes `Conductor.narration(for:)` — every
  /// read stage complete, "Developing" now the running one.
  mutating func settle(narration: [String]) {
    isSettled = true
    steps = narration
    activeIndex = max(0, narration.count - 1)
  }

  /// Everything the ceremony named has finished: nothing is shown as running.
  mutating func finish() {
    activeIndex = steps.count
  }

  /// A ceremony for a photograph this session has already read (a camera
  /// switch): those stages are genuinely done, so the panel opens saying so
  /// rather than replaying a read that is not happening.
  static func settled(narration: [String]) -> DevelopCeremony {
    var ceremony = DevelopCeremony()
    ceremony.settle(narration: narration)
    return ceremony
  }
}

/// The resolution ladder.
///
/// A develop shows a genuine small render of the photograph first, then
/// replaces it with the full-size one. **Both rungs are real renders** of the
/// real recipe from the one reading — the photograph resolves on screen
/// because the machine is genuinely computing it twice at increasing
/// resolution, not because a timer is pretending it is.
///
/// The first rung is display-only by construction: it is never handed to
/// `applyDeveloped`, never entered in the Library, never written to
/// `PreviewCache`, and never reaches `save()`. The frame the user keeps is
/// produced by exactly the same full-size render as before, byte for byte.
enum DevelopLadder {
  /// longest edge of the first rung — 1/16 the pixels of a 2048 preview
  static let firstRung = 512

  /// The first rung for a device whose preview cap is `previewEdge`, or nil
  /// where the full preview is already small enough that a second render
  /// costs more than the early look is worth (the universal tier already
  /// renders its preview at 1024).
  static func firstRungEdge(previewEdge: Int) -> Int? {
    previewEdge >= 1536 ? firstRung : nil
  }
}
