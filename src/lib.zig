const std = @import("std");

pub const Kind = enum { glob, regex };
/// Half-open byte offsets into the caller's source; regex markers are excluded.
pub const Segment = struct { kind: Kind, start: usize, end: usize };
pub const Diagnostic = struct {
    kind: enum { unexpected_close, unclosed_excerpt, dangling_escape },
    offset: usize,
};
pub const Result = union(enum) {
    segments: []Segment,
    diagnostic: Diagnostic,

    pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
        switch (self) {
            .segments => |segments| allocator.free(segments),
            .diagnostic => {},
        }
    }
};

/// Frame excerpts by balancing unescaped brackets. This does not validate regex.
/// Escape sequences stay byte-for-byte intact in both kinds of source span.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!Result {
    var output: std.ArrayList(Segment) = .empty;
    defer output.deinit(allocator);
    var openings: std.ArrayList(usize) = .empty;
    defer openings.deinit(allocator);
    var glob_start: usize = 0;
    var i: usize = 0;
    while (i < source.len) {
        switch (source[i]) {
            '\\' => {
                if (i + 1 == source.len) return .{ .diagnostic = .{ .kind = .dangling_escape, .offset = i } };
                i += 2;
                continue;
            },
            '[' => {
                if (openings.items.len == 0 and glob_start < i)
                    try output.append(allocator, .{ .kind = .glob, .start = glob_start, .end = i });
                try openings.append(allocator, i);
            },
            ']' => {
                const start = openings.pop() orelse return .{ .diagnostic = .{ .kind = .unexpected_close, .offset = i } };
                if (openings.items.len == 0) {
                    try output.append(allocator, .{ .kind = .regex, .start = start + 1, .end = i });
                    glob_start = i + 1;
                }
            },
            else => {},
        }
        i += 1;
    }
    if (openings.items.len != 0)
        return .{ .diagnostic = .{ .kind = .unclosed_excerpt, .offset = openings.items[0] } };
    if (glob_start < source.len)
        try output.append(allocator, .{ .kind = .glob, .start = glob_start, .end = source.len });
    return .{ .segments = try output.toOwnedSlice(allocator) };
}
