const std = @import("std");
const panic = std.debug.panic;
const cpu = std.builtin.cpu;
const os = std.builtin.os;
const fs = std.fs;
const path = std.fs.path;
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const Mode = std.builtin.Mode;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("only-sh", "src/main.zig");
    createOutputDir(b, exe);
    exe.setTarget(b.standardTargetOptions(if (os.tag != .linux) .{} else .{
        .default_target = .{
            .cpu_arch = cpu.arch,
            .os_tag = os.tag,
            .abi = switch (cpu.arch) {
                .aarch64 => .musleabi,
                .arm => .musleabihf,
                else => .musl,
            },
        },
    }));
    exe.setBuildMode(b.standardReleaseOptions());
    if (exe.build_mode == Mode.ReleaseSmall or exe.build_mode == Mode.ReleaseFast) exe.strip = true;
    exe.single_threaded = true;
    exe.linkLibC();
    exe.install();
}

fn createOutputDir(b: *Builder, exe: *LibExeObjStep) void {
    const cwd_path = fs.realpathAlloc(b.allocator, ".") catch unreachable;
    const out_path = path.join(b.allocator, &[_][]const u8{cwd_path, "out"}) catch unreachable;
    defer b.allocator.free(cwd_path);
    defer b.allocator.free(out_path);
    fs.makeDirAbsolute(out_path) catch |err| {
        if (err != error.PathAlreadyExists) panic("{}\n", .{err});
    };
    exe.setOutputDir("out");
}
