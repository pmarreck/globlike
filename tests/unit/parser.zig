const std = @import("std");
const g = @import("globlike");
const t = std.testing;

const Expected = struct { kind: g.Kind, text: []const u8 };

fn segments(source: []const u8, expected: []const Expected) !void {
    const result = try g.parse(t.allocator, source);
    defer result.deinit(t.allocator);
    try t.expect(result == .segments);
    try t.expectEqual(expected.len, result.segments.len);
    for (expected, result.segments) |want, got| {
        try t.expectEqual(want.kind, got.kind);
        try t.expectEqualStrings(want.text, source[got.start..got.end]);
    }
}

test "empty input and ordinary glob classes remain glob segments" {
    try segments("", &.{});
    try segments("a/[abc]/[!d-f]/[[:digit:]]/*/**", &.{.{ .kind = .glob, .text = "a/[abc]/[!d-f]/[[:digit:]]/*/**" }});
    try segments("[a%r{}]", &.{.{ .kind = .glob, .text = "[a%r{}]" }});
    try segments("a]b[", &.{.{ .kind = .glob, .text = "a]b[" }});
}

test "excerpts retain intervening glob text and regex escapes" {
    try segments("/%r[Users|home]/%r{\\p{L}+}/**", &.{
        .{ .kind = .glob, .text = "/" },
        .{ .kind = .regex, .text = "Users|home" },
        .{ .kind = .glob, .text = "/" },
        .{ .kind = .regex, .text = "\\p{L}+" },
        .{ .kind = .glob, .text = "/**" },
    });
}

test "each paired delimiter nests only its own pair" {
    try segments("%r[[a-z][0-9]+]", &.{.{ .kind = .regex, .text = "[a-z][0-9]+" }});
    try segments("%r{\\p{L}{2}}", &.{.{ .kind = .regex, .text = "\\p{L}{2}" }});
    try segments("%r((a|b)+)", &.{.{ .kind = .regex, .text = "(a|b)+" }});
    try segments("%r<a<b>c>", &.{.{ .kind = .regex, .text = "a<b>c" }});
    try segments("%r{[]]}", &.{.{ .kind = .regex, .text = "[]]" }});
    try segments("%r{[[]}", &.{.{ .kind = .regex, .text = "[[]" }});
}

test "literal markers and escaped delimiters remain distinct" {
    try segments("file\\[draft\\].txt", &.{.{ .kind = .glob, .text = "file\\[draft\\].txt" }});
    try segments("\\%r{abc}", &.{.{ .kind = .glob, .text = "\\%r{abc}" }});
    try segments("%r[ \\]]", &.{.{ .kind = .regex, .text = " \\]" }});
    try segments("%r{a\\}b}", &.{.{ .kind = .regex, .text = "a\\}b" }});
    try segments("%r/file", &.{.{ .kind = .glob, .text = "%r/file" }});
}

test "escaped backslashes do not swallow following markers" {
    try segments("\\\\%r[a]", &.{
        .{ .kind = .glob, .text = "\\\\" },
        .{ .kind = .regex, .text = "a" },
    });
    try segments("%r[\\\\]", &.{.{ .kind = .regex, .text = "\\\\" }});
    try segments("\\\\\\%r{a}", &.{.{ .kind = .glob, .text = "\\\\\\%r{a}" }});
}

test "adjacent empty sigils and suffix text preserve boundaries" {
    try segments("%r[a]%r{}%r(b)i", &.{
        .{ .kind = .regex, .text = "a" },
        .{ .kind = .regex, .text = "" },
        .{ .kind = .regex, .text = "b" },
        .{ .kind = .glob, .text = "i" },
    });
}

test "malformed sigils report byte offsets without partial success" {
    const Case = struct { source: []const u8, expected: g.Diagnostic };
    const cases = [_]Case{
        .{ .source = "a%r[bc", .expected = .{ .kind = .unclosed_excerpt, .offset = 1 } },
        .{ .source = "abc\\", .expected = .{ .kind = .dangling_escape, .offset = 3 } },
        .{ .source = "%r[a\\", .expected = .{ .kind = .dangling_escape, .offset = 4 } },
        .{ .source = "é%r{x", .expected = .{ .kind = .unclosed_excerpt, .offset = 2 } },
        .{ .source = "%r{a{b}", .expected = .{ .kind = .unclosed_excerpt, .offset = 0 } },
    };
    for (cases) |case| {
        const result = try g.parse(t.allocator, case.source);
        defer result.deinit(t.allocator);
        try t.expect(result == .diagnostic);
        try t.expectEqualDeep(case.expected, result.diagnostic);
    }
}

fn allocationCase(allocator: std.mem.Allocator, source: []const u8) !void {
    const result = try g.parse(allocator, source);
    defer result.deinit(allocator);
}

test "every allocation failure releases class indexes and partial segments" {
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a%r[[b]]/[abc]%r[c]d%r[e]f%r[g]h%r[i]j"});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a%r[[b]]/%r[c"});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a%r[[b]]/%r[c\\"});
}

test "deep sigil nesting is iterative" {
    const depth = 10000;
    const source = try t.allocator.alloc(u8, depth * 2 + 3);
    defer t.allocator.free(source);
    @memcpy(source[0..2], "%r");
    @memset(source[2 .. depth + 2], '(');
    source[depth + 2] = 'a';
    @memset(source[depth + 3 ..], ')');
    const result = try g.parse(t.allocator, source);
    defer result.deinit(t.allocator);
    try t.expect(result == .segments);
    try t.expectEqual(@as(usize, 1), result.segments.len);
    try t.expectEqualDeep(g.Segment{ .kind = .regex, .start = 3, .end = source.len - 1 }, result.segments[0]);
}

test "Unicode bytes and source spans reconstruct all delimiters losslessly" {
    const inputs = [_][]const u8{
        "",
        "é/%r{\\p{L}+}/日本語",
        "%r[a]%r{}%r(b)%r<c>",
        "file\\[draft\\].txt",
        "%r[ \\]]",
        "%r[ ]\\]",
        "%r[[[:alpha:]]+]",
        "a/[abc]/*/b?/**",
    };
    for (inputs) |source| {
        const result = try g.parse(t.allocator, source);
        defer result.deinit(t.allocator);
        try t.expect(result == .segments);
        var reconstructed: std.ArrayList(u8) = .empty;
        defer reconstructed.deinit(t.allocator);
        for (result.segments) |segment| {
            if (segment.kind == .regex) try reconstructed.appendSlice(t.allocator, source[segment.start - 3 .. segment.start]);
            try reconstructed.appendSlice(t.allocator, source[segment.start..segment.end]);
            if (segment.kind == .regex) try reconstructed.append(t.allocator, source[segment.end]);
        }
        try t.expectEqualStrings(source, reconstructed.items);
    }
}
