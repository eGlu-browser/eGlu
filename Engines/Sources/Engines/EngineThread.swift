import Foundation

/// The one thread a `Grammar` runs on, as its actor's executor.
///
/// Harper keeps caches per thread (`thread_local`): the automaton builders
/// its spelling suggestions use, and patterns its parser shares; and with
/// Harper's `concurrent` feature off, what it shares is `Rc`, whose counts
/// are not atomic. An actor on Swift's shared pool runs each call on
/// whichever pool thread is free, so every thread it landed on would build
/// its own caches, `warmUp` would warm only the first, and an `Rc` made on
/// one thread would be counted on another. Here every call into one
/// linter, from its first lint to its free, is on one thread.
final class EngineThread: SerialExecutor, @unchecked Sendable {
    // @unchecked: `work`, `thread` and `finishing` are only touched with
    // `condition` locked.
    private let condition = NSCondition()
    private var work: [@Sendable () -> Void] = []
    private var thread: Thread?
    private var finishing = false
    private let name: String

    init(name: String) {
        self.name = name
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        submit { job.runSynchronously(on: executor) }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    /// Runs `last` after the work already given, then ends the thread. If no
    /// work ever came, nothing ran on a thread of its own and `last` runs
    /// here.
    func finish(with last: @escaping @Sendable () -> Void) {
        condition.lock()
        guard thread != nil else {
            condition.unlock()
            last()
            return
        }
        work.append(last)
        finishing = true
        condition.signal()
        condition.unlock()
    }

    private func submit(_ body: @escaping @Sendable () -> Void) {
        condition.lock()
        defer { condition.unlock() }
        work.append(body)
        if thread != nil {
            condition.signal()
            return
        }
        // Started on the first call rather than in init: a Grammar whose
        // settings fail never starts one.
        let thread = Thread { [self] in run() }
        thread.name = name
        // The stack Rust gives the threads it starts itself, the ones
        // Harper is written and tested on; Thread's own is a quarter of it.
        thread.stackSize = 2 << 20
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    private func run() {
        while true {
            condition.lock()
            while work.isEmpty && !finishing {
                condition.wait()
            }
            if work.isEmpty {
                // The Thread keeps its block, and the block keeps self:
                // letting go of the Thread here is what frees them both.
                thread = nil
                condition.unlock()
                return
            }
            let next = work.removeFirst()
            condition.unlock()
            // A thread of our own has no run loop to drain what Foundation
            // autoreleases while decoding the engine's answers.
            autoreleasepool { next() }
        }
    }
}
