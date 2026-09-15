const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseFast)") orelse .ReleaseFast;
    const lib = b.addModule("globlike", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(b.addLibrary(.{ .name = "globlike", .linkage = .static, .root_module = lib }));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/unit/parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "globlike", .module = lib }},
    }) });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);
}
