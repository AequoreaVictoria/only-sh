const std = @import("std");
const c_heap = std.heap.c_allocator;
const fmt = std.fmt;
const mem = std.mem;
const print = std.debug.warn;
const process = std.process;
const Allocator = mem.Allocator;
const c = @cImport({
    @cInclude("unistd.h");
});

// The shell filename must be at least one character followed by the '-only' tag
const MIN_NAME = 6;

pub fn main() !u8 {
    const status = enum(u8) { OK, INPUT_ERROR, VALIDATION_ERROR };

    const in_argv = try process.argsAlloc(c_heap);
    defer c_heap.free(in_argv);

    if (!validFilename(in_argv[0])) {
        print("your shell must be named like '<command>-only', e.g. rsync-only\n", .{});
        return @enumToInt(status.INPUT_ERROR);
    }

    if (!validArgumentCount(in_argv)) {
        print("wrong command\n", .{});
        return @enumToInt(status.INPUT_ERROR);
    }

    // The command will always be the last value in in_argv[]
    const out_argv = ARGV.init(c_heap, in_argv[in_argv.len - 1]) catch |err| {
        if (err == error.QUOTATION_ERROR) {
            print("invalid quotation\n", .{});
            return @enumToInt(status.INPUT_ERROR);
        } else return err;
    };
    defer out_argv.free();

    if (!try validCommand(c_heap, in_argv[0], out_argv.args[0].?, out_argv.size[0])) {
        print("wrong command\n", .{});
        return @enumToInt(status.VALIDATION_ERROR);
    }

    const code = c.execvp(out_argv.args[0].?, out_argv.args);
    if (code == -1) {
        print("command failure\n", .{});
        return @enumToInt(status.INPUT_ERROR);
    } else return @enumToInt(status.OK);
}

// At minimum this shell will be called like 'sh -c "command arg1..argN"'
fn validArgumentCount(argv: [][]u8) bool {
    return !(argv.len < 3);
}

// The shell filename must be MIN_NAME long and end in '-only'
fn validFilename(arg: []const u8) bool {
    if ((arg.len < MIN_NAME) or (!mem.eql(u8, "-only", arg[(arg.len - 5)..arg.len]))) return false;
    return true;
}

// Compares the check[] command against the command extracted from arg0[]
fn validCommand(heap: *Allocator, arg0: []const u8, check: [*:0]const u8, check_size: usize) !bool {
    const arg0_size = arg0.len - MIN_NAME;

    var arg0_idx: usize = arg0_size;
    while (arg0_idx > 0) : (arg0_idx -= 1) if (arg0[arg0_idx] == '/') break;

    const valid_size = arg0_size - arg0_idx;
    if (check_size != valid_size) return false;

    // Set position to after the / separator
    arg0_idx += 1;
    var valid = try heap.alloc(u8, valid_size);
    defer heap.free(valid);
    for (valid) |char, i| {
        valid[i] = arg0[arg0_idx];
        arg0_idx += 1;
    }

    // Set position to before the 0 terminator
    var check_idx = check_size - 1;
    while (check_idx > 0) : (check_idx -= 1) if (check[check_idx] != valid[check_idx]) return false;

    return true;
}

const ARGV = struct {
    heap: *Allocator,
    args: [*:null]?[*:0]u8,
    size: []usize,
    bytes: usize,
    const Self = @This();

    fn init(heap: *Allocator, arg: []const u8) !Self {
        const input = fmt.trim(arg);
        const args_count = try count(input);
        const size = try measure(heap, input, args_count);
        const bytes = @sizeOf(usize) * (args_count + 1); // +1 for the null terminator
        const buffer = try heap.alignedAlloc(u8, @alignOf(?*u8), bytes);

        var args = mem.bytesAsSlice(?[*:0]u8, buffer);
        for (size) |s, i| {
            var string = try heap.alloc(u8, s + 1); // +1 for the 0 terminator
            for (string) |char, ch| string[ch] = 0;
            args[i] = @ptrCast(*[*:0]u8, &string).*;
        }
        args[args_count] = null;

        var in_single_quotes = false;
        var in_double_quotes = false;
        var previously_space = false;
        var string: usize = 0;
        var char: usize = 0;
        for (input) |ch| switch (ch) {
            ' ' => {
                if (in_single_quotes or in_double_quotes) {
                    args[string].?[char] = ch;
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
                args[string].?[char] = ch;
                char += 1;
            },
        };

        return Self{
            .heap = heap,
            .args = @ptrCast(*[*:null]?[*:0]u8, &args).*,
            .size = size,
            .bytes = bytes,
        };
    }

    fn free(s: *const Self) void {
        for (s.size) |size, i| {
            const string = @ptrCast([*]u8, s.args[i]);
            s.heap.free(string[0..size]);
        }
        s.heap.free(s.size);
        const array = @ptrCast([*]u8, s.args);
        s.heap.free(array[0..s.bytes]);
    }

    // Returns the number of arguments in input[]
    fn count(input: []const u8) !usize {
        var spaces: usize = 0;
        var in_single_quotes = false;
        var in_double_quotes = false;
        var previously_space = false;
        for (input) |ch| switch (ch) {
            ' ' => {
                if ((!(in_single_quotes or in_double_quotes)) and (!previously_space)) {
                    previously_space = true;
                    spaces += 1;
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
        return spaces + 1;
    }

    // Returns an array with the byte sizes of each argument in input[]
    fn measure(heap: *Allocator, input: []const u8, length: usize) ![]usize {
        var table = try heap.alloc(usize, length);
        var in_single_quotes = false;
        var in_double_quotes = false;
        var previously_space = false;
        var string: usize = 0;
        var bytes: usize = 0;
        for (input) |ch| switch (ch) {
            ' ' => {
                if (in_single_quotes or in_double_quotes) {
                    bytes += 1;
                } else if (!previously_space) {
                    previously_space = true;
                    table[string] = bytes;
                    string += 1;
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
        table[string] = bytes;
        return table;
    }
};
