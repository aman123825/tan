/// Shared timing for hands-free listening tasks.
///
/// A response gets a brief visual feedback beat, then the next trial appears.
/// Its audio starts after a 1.2 second breathing room.
const Duration kTrialFeedbackDelay = Duration(milliseconds: 300);
const Duration kTrialPrePlayDelay = Duration(milliseconds: 1200);
