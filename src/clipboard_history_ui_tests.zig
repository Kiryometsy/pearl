//! Focused compositor-free entry point; also registered in the core suite.
test {
    _ = @import("services/clipboard_history_presentation_tests.zig");
    _ = @import("services/clipboard_history_session_tests.zig");
}
