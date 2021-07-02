const std = @import("std");
const mem = std.mem;
const print = std.debug.warn;
const basename = std.fs.path.basename;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var arena_heap = &arena.allocator;

    const input_argv = std.os.argv;
    const name = basename(input_argv[0][0 .. mem.len(input_argv[0])]);

    // name[] needs to fit the '<command>-only' naming convention
    if (!mem.eql(u8, "-only", name[name.len - "-only".len ..])) {
        print("wrong filename\n", .{});
        return std.c.ENOTSUP;
    }

    // This shell will be called like 'sh -c "command arg1..argN"'
    // cmd_pos holds the position of the string provided to '-c'
    const cmd_pos = getCmdPos(input_argv) catch {
        print("wrong command\n", .{});
        return std.c.EINVAL;
    };

    // Returns a null-terminated ARGV array for use with execvpeZ_expandArg0()
    const exec_argv = mkArgv(arena_heap, input_argv[cmd_pos]) catch |err| {
        if (err == error.QUOTATION_ERROR) {
            print("invalid quotation\n", .{});
            return std.c.EINVAL;
        } else return err;
    };

    // The program names in name[] and exec_argv0[] must match
    const exec_argv0 = basename(exec_argv[0].?[0 .. mem.len(exec_argv[0].?)]);
    if (!mem.eql(u8, name[0 .. name.len - "-only".len], exec_argv0)) {
        print("wrong command\n", .{});
        return std.c.EACCES;
    }

    var envp = @ptrCast([*:null]?[*:0]u8, std.os.environ.ptr);
    const err = std.os.execvpeZ_expandArg0(.expand, exec_argv[0].?, exec_argv, envp);
    switch (err) {
        std.os.ExecveError.AccessDenied => {
            print("access denied\n", .{});
            return std.c.EACCES;
        },
        std.os.ExecveError.FileBusy => {
            print("file busy\n", .{});
            return std.c.EBUSY;
        },
        std.os.ExecveError.FileNotFound => {
            print("file not found\n", .{});
            return std.c.ENOENT;
        },
        std.os.ExecveError.FileSystem => {
            print("file system error\n", .{});
            return std.c.EIO;
        },
        std.os.ExecveError.InvalidExe => {
            print("invalid executable\n", .{});
            return std.c.ENOEXEC;
        },
        std.os.ExecveError.IsDir => {
            print("file is directory\n", .{});
            return std.c.EISDIR;
        },
        std.os.ExecveError.NameTooLong => {
            print("name too long\n", .{});
            return std.c.ENAMETOOLONG;
        },
        std.os.ExecveError.NotDir => {
            print("file is not directory\n", .{});
            return std.c.ENOTDIR;
        },
        std.os.ExecveError.ProcessFdQuotaExceeded => {
            print("process fd quota exceeded\n", .{});
            return std.c.EMFILE;
        },
        std.os.ExecveError.SystemFdQuotaExceeded => {
            print("system fd quota exceeded\n", .{});
            return std.c.ENFILE;
        },
        std.os.ExecveError.SystemResources => {
            print("no available system resources\n", .{});
            return std.c.ENOMEM;
        },
        std.os.ExecveError.Unexpected => {
            print("unexpected error\n", .{});
            return err;
        },
    }
}

fn getCmdPos(argv: [][*:0]u8) !usize {
    var pos: ?usize = null;
    for (argv) |a, i| {
        if (mem.eql(u8, "-c", a[0 .. mem.len(a)])) {
            if (pos != null) return error.DUPLICATE_POS;
            if (i + 1 >= argv.len) return error.OVERFLOW_POS;
            pos = i + 1;
        }
    }
    if (pos == null) return error.NULL_POS;
    return pos.?;
}

fn mkArgv(heap: *mem.Allocator, arg: [*:0]const u8) ![*:null]?[*:0]const u8 {
    const input = mem.trim(u8, arg[0 .. mem.len(arg)], &std.ascii.spaces);

    // 'count' is the number of argv elements in 'input'
    var count: usize = 0;
    var in_single_quotes = false;
    var in_double_quotes = false;
    var previously_space = false;
    for (input) |ch| switch (ch) {
        ' ' => {
            if ((!(in_single_quotes or in_double_quotes)) and (!previously_space)) {
                previously_space = true;
                count += 1;
            }
        },
        '\'' => {
            previously_space = false;
            in_single_quotes = !in_single_quotes;
        },
        '"' => {
            previously_space = false;
            in_double_quotes = !in_double_quotes;
        },
        else => previously_space = false,
    };
    if (in_single_quotes or in_double_quotes) return error.QUOTATION_ERROR;
    count += 1;

    // 'size[]' is the byte count of each argv element in 'input'
    var size = try heap.alloc(usize, count);
    var size_idx: usize = 0;
    var bytes: usize = 0;
    in_single_quotes = false;
    in_double_quotes = false;
    previously_space = false;
    for (input) |ch| switch (ch) {
        ' ' => {
            if (in_single_quotes or in_double_quotes) {
                bytes += 1;
            } else if (!previously_space) {
                previously_space = true;
                size[size_idx] = bytes;
                size_idx += 1;
                bytes = 0;
            }
        },
        '\'' => {
            previously_space = false;
            in_single_quotes = !in_single_quotes;
        },
        '"' => {
            previously_space = false;
            in_double_quotes = !in_double_quotes;
        },
        else => {
            previously_space = false;
            bytes += 1;
        },
    };
    size[size_idx] = bytes;

    const argv = try heap.allocSentinel(?[*:0]u8, count, null);
    for (size) |s, i| {
        argv[i] = try heap.allocSentinel(u8, s, 0);
    }

    // Copy the argv elements in 'input' into 'argv[]' and return it
    var string: usize = 0;
    var char: usize = 0;
    in_single_quotes = false;
    in_double_quotes = false;
    previously_space = false;
    for (input) |ch| switch (ch) {
        ' ' => {
            if (in_single_quotes or in_double_quotes) {
                argv[string].?[char] = ch;
                char += 1;
            } else if (!previously_space) {
                previously_space = true;
                string += 1;
                char = 0;
            }
        },
        '\'' => {
            previously_space = false;
            in_single_quotes = !in_single_quotes;
        },
        '"' => {
            previously_space = false;
            in_double_quotes = !in_double_quotes;
        },
        else => {
            previously_space = false;
            argv[string].?[char] = ch;
            char += 1;
        },
    };

    return argv;
}
