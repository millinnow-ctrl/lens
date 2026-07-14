import Darwin
import Foundation

/// Real peak-memory probe using Mach `phys_footprint` — the same number Xcode's
/// memory graph and jetsam use. Works on device and simulator; the benchmark
/// harness (R60-7) samples it around renders so the "peak memory" deliverable is
/// measured, not guessed.
enum MemoryProbe {
  /// Current physical footprint in bytes, or 0 if the query fails.
  static func footprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
    let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
      ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
      }
    }
    return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
  }

  static func footprintMB() -> Double { Double(footprintBytes()) / (1024 * 1024) }
}

/// Wall-clock timing of a block, in milliseconds. Deterministic on any device.
enum Stopwatch {
  static func millis(_ block: () -> Void) -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    block()
    return (CFAbsoluteTimeGetCurrent() - start) * 1000
  }
}
