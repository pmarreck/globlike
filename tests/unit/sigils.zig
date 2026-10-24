const std = @import("std");
const g = @import("globlike");
const t = std.testing;

fn classify(source: []const u8, candidates: []const []const u8, expected: []const bool) !void {
    var compiled = try g.compile(t.allocator, source, .{});
    try t.expect(compiled == .pattern);
    defer compiled.pattern.deinit();
    try t.expectEqual(candidates.len, expected.len);
    for (candidates, expected) |path, want| {
        const result = compiled.pattern.matches(path);
        try t.expect(result == .matched);
        try t.expectEqual(want, result.matched);
    }
}

test "paired regex sigils retain exact sequence semantics inside whole-path globs" {
    for ([_][]const u8{ "%r[abc]", "%r{abc}", "%r(abc)", "%r<abc>" }) |source|
        try classify(source, &.{ "abc", "a", "b", "c", "xabc", "abc\n", source }, &.{ true, false, false, false, false, false, false });
    try classify("**/photo-%r{[0-9]{4}}.jpg", &.{ "photo-2026.jpg", "a/photo-1234.jpg", "a/b/photo-0000.jpg", "photo-123.jpg", "photo-abcd.jpg", "photo-2026.jpg\n" }, &.{ true, true, true, false, false, false });
    try classify("%r{/home/[^/]+/}*.jpg", &.{ "/home/alex/a.jpg", "/home/alex/b/a.jpg", "/home//a.jpg", "/home/alex/a.png" }, &.{ true, false, false, false });
}

test "ordinary glob classes classify characters instead of regex sequences" {
    try classify("[abc]", &.{ "a", "b", "c", "abc", "[abc]", "/", "" }, &.{ true, true, true, false, false, false, false });
    for ([_][]const u8{ "[!a-c]", "[^a-c]" }) |source|
        try classify(source, &.{ "a", "c", "d", "日", "/", "", "dd", "\n" }, &.{ false, false, true, true, false, false, false, true });
    try classify("[é日]", &.{ "é", "日", "e", "é日", "/" }, &.{ true, true, false, false, false });
    try classify("[[:digit:]][a-c]", &.{ "0a", "9c", "aa", "0d", "00a", "/a" }, &.{ true, true, false, false, false, false });
}

test "glob bracket edge cases and escaped bytes cannot acquire regex meaning" {
    try classify("[]a]", &.{ "]", "a", "[", "[]a]" }, &.{ true, true, false, false });
    try classify("[[]", &.{ "[", "]", "[[]" }, &.{ true, false, false });
    try classify("[\\d]", &.{ "d", "4", "\\", "dd" }, &.{ true, false, false, false });
    try classify("[a\\-z]", &.{ "a", "-", "z", "b" }, &.{ true, true, true, false });
    try classify("[a%r{}]", &.{ "a", "%", "r", "{", "}", "ar", "" }, &.{ true, true, true, true, true, false, false });
    try classify("[abc", &.{ "[abc", "a", "abc" }, &.{ true, false, false });
    try classify("[/abc/]", &.{ "[/abc/]", "a", "/", "abc" }, &.{ true, false, false, false });
    try classify("\\%r{abc}", &.{ "%r{abc}", "abc", "%r{a}" }, &.{ true, false, false });
}

test "sigil suffixes remain glob text and inline flags are scoped" {
    try classify("%r[abc]i", &.{ "abci", "abc", "ABC", "ABCi" }, &.{ true, false, false, false });
    try classify("%r{(?i)abc}x", &.{ "abcx", "ABCx", "ABCX", "xabcx" }, &.{ true, true, false, false });
    try classify("%r{a\\}b}", &.{ "a}b", "ab", "a\\}b" }, &.{ true, false, false });
    try classify("%r((a|b)+)", &.{ "a", "abba", "c", "", "(a)" }, &.{ true, true, false, false, false });
}

test "malformed sigils preserve byte offsets including explicit mode prefixes" {
    for ([_][]const u8{ "%r[a", "%r{a", "%r(a", "%r<a" }) |source| {
        var result = try g.compile(t.allocator, source, .{});
        defer if (result == .pattern) result.pattern.deinit();
        try t.expect(result == .diagnostic);
        try t.expectEqual(.unclosed_excerpt, result.diagnostic.kind);
        try t.expectEqual(@as(?usize, 0), result.diagnostic.offset);
    }
    var result = try g.compile(t.allocator, "glob:é%r{abc", .{});
    defer if (result == .pattern) result.pattern.deinit();
    try t.expect(result == .diagnostic);
    try t.expectEqual(@as(?usize, 7), result.diagnostic.offset);
    var invalid = try g.compile(t.allocator, "glob:é%r{(}", .{});
    defer if (invalid == .pattern) invalid.pattern.deinit();
    try t.expect(invalid == .diagnostic);
    try t.expectEqual(.regex_syntax, invalid.diagnostic.kind);
    try t.expectEqual(@as(?usize, 11), invalid.diagnostic.offset);
}

test "locale collating and equivalence classes are rejected explicitly" {
    for ([_][]const u8{ "[[.a.]]", "[[=a=]]" }) |source| {
        var result = try g.compile(t.allocator, source, .{});
        defer if (result == .pattern) result.pattern.deinit();
        try t.expect(result == .diagnostic);
        try t.expectEqual(.unsupported_glob_class, result.diagnostic.kind);
        try t.expectEqual(@as(i32, 0), result.diagnostic.engine_code);
    }
}

test "ordinary class punctuation cannot turn into PCRE2 POSIX syntax" {
    try classify("[:digit:]", &.{ ":", "d", "i", "g", "t", "1", "a" }, &.{ true, true, true, true, true, false, false });
    try classify("[.a.]", &.{ ".", "a", "b" }, &.{ true, true, false });
    try classify("[=a=]", &.{ "=", "a", "b" }, &.{ true, true, false });
    try classify("[\\:digit:]", &.{ ":", "d", "1" }, &.{ true, true, false });
}

test "ordinary glob subset agrees with independent libc fnmatch over candidate sets" {
    if (comptime @import("builtin").os.tag != .linux) return error.SkipZigTest;
    const c = @cImport({
        @cInclude("fnmatch.h");
    });
    // musl treats backslashes inside classes as literal members. Bash removes
    // their escaping role before matching. musl also accepts slash-containing
    // classes; Bash pathname expansion treats them literally. Both are fenced below.
    const patterns = [_][:0]const u8{ "*", "?", "[ab]", "[!ab]", "[^ab]", "[a-c]", "[]a]", "[[]", "[-ab]", "[ab-]", "[[:digit:]]", "[[:alpha:]]", "[[:punct:]]", "[[:space:]]", "a[!b]", "*[ab]?", "a/*", "a/[ab]", "[abc", "[]", "[[:digit:]", "[a%r{}]" };
    const alphabet = "ab1/[]-d.%r{} \\\n";
    for (patterns) |source| {
        var compiled = try g.compile(t.allocator, source, .{});
        if (compiled == .diagnostic) {
            var message: [256]u8 = undefined;
            std.debug.print("fnmatch pattern failed to compile: {s}: {s}\n", .{ source, compiled.diagnostic.message(&message) });
        }
        try t.expect(compiled == .pattern);
        defer compiled.pattern.deinit();
        var candidate: [4:0]u8 = @splat(0);
        // Exhaust all strings of length 0..3 over the declared ASCII alphabet.
        for (0..4) |length| {
            const count = std.math.pow(usize, alphabet.len, length);
            for (0..count) |encoded| {
                var digits = encoded;
                for (0..length) |i| {
                    candidate[i] = alphabet[digits % alphabet.len];
                    digits /= alphabet.len;
                }
                candidate[length] = 0;
                const expected = c.fnmatch(source.ptr, &candidate, c.FNM_PATHNAME) == 0;
                const got = compiled.pattern.matches(candidate[0..length]);
                try t.expect(got == .matched);
                if (expected != got.matched) std.debug.print("fnmatch disagreement: pattern={s}, candidate={s}\n", .{ source, candidate[0..length] });
                try t.expectEqual(expected, got.matched);
            }
        }
    }
}

test "escaped glob class hyphens follow Bash rather than musl's literal backslash" {
    // Bash 5.3 [[ value == $pattern ]] was checked with pattern [a\-c]:
    // a, c, and - match; b and backslash do not. Keep that set explicit.
    try classify("[a\\-c]", &.{ "a", "b", "c", "-", "\\" }, &.{ true, false, true, true, false });
    if (comptime @import("builtin").os.tag != .linux or @import("builtin").abi != .musl) return;
    const c = @cImport({
        @cInclude("fnmatch.h");
    });
    try t.expectEqual(@as(c_int, 0), c.fnmatch("[a\\-c]", "b", c.FNM_PATHNAME));
    try t.expect(c.fnmatch("[a\\-c]", "-", c.FNM_PATHNAME) != 0);
}

test "slash-containing brackets follow Bash pathname expansion" {
    // In a disposable directory containing a, b, and [/abc/], Bash compgen -G
    // '[/abc/]' returns only [/abc/]. String case/[[ matching is different.
    try classify("[/abc/]", &.{ "[/abc/]", "a", "b", "/" }, &.{ true, false, false, false });
    if (comptime @import("builtin").os.tag != .linux or @import("builtin").abi != .musl) return;
    const c = @cImport({
        @cInclude("fnmatch.h");
    });
    try t.expectEqual(@as(c_int, 0), c.fnmatch("[/abc/]", "a", c.FNM_PATHNAME));
    try t.expect(c.fnmatch("[/abc/]", "[/abc/]", c.FNM_PATHNAME) != 0);
}
