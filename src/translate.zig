const std = @import("std");
const g = @import("lib.zig");

pub const Translation = struct {
    text: std.ArrayList(u8) = .empty,
    positions: std.ArrayList(usize) = .empty,
    diagnostic: ?g.Diagnostic = null,

    pub fn deinit(self: *Translation, allocator: std.mem.Allocator) void {
        self.text.deinit(allocator);
        self.positions.deinit(allocator);
    }

    fn emit(self: *Translation, allocator: std.mem.Allocator, text: []const u8, offset: usize) !void {
        try self.text.appendSlice(allocator, text);
        try self.positions.appendNTimes(allocator, offset, text.len);
    }

    fn literal(self: *Translation, allocator: std.mem.Allocator, char: u8, offset: usize) !void {
        if (std.mem.indexOfScalar(u8, "\\.^$|()[]{}*+?", char) != null) try self.emit(allocator, "\\", offset);
        try self.emit(allocator, &.{char}, offset);
    }
};

pub fn translate(allocator: std.mem.Allocator, source: []const u8, raw_regex: bool) !Translation {
    var output: Translation = .{};
    errdefer output.deinit(allocator);
    if (raw_regex) {
        for (source, 0..) |char, i| try output.emit(allocator, &.{char}, i);
        return output;
    }
    const parsed = try g.parse(allocator, source);
    defer parsed.deinit(allocator);
    if (parsed == .diagnostic) return .{ .diagnostic = parsed.diagnostic };
    try output.emit(allocator, "\\A(?:", 0);
    for (parsed.segments) |segment| {
        if (segment.kind == .regex) {
            try output.emit(allocator, "(?-i:", segment.start);
            for (source[segment.start..segment.end], segment.start..) |char, i| try output.emit(allocator, &.{char}, i);
            try output.emit(allocator, ")", segment.end);
            continue;
        }
        var i = segment.start;
        while (i < segment.end) {
            switch (source[i]) {
                '\\' => {
                    i += 1;
                    try output.literal(allocator, source[i], i);
                },
                '*' => {
                    if (i + 1 < segment.end and source[i + 1] == '*') {
                        if (i + 2 < segment.end and source[i + 2] == '/') {
                            try output.emit(allocator, "(?:[^/]+/)*", i);
                            i += 2;
                        } else {
                            try output.emit(allocator, "(?s:.*)", i);
                            i += 1;
                        }
                    } else try output.emit(allocator, "[^/]*", i);
                },
                '?' => try output.emit(allocator, "[^/]", i),
                else => try output.literal(allocator, source[i], i),
            }
            i += 1;
        }
    }
    try output.emit(allocator, ")\\z", source.len);
    return output;
}
