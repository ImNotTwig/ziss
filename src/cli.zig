const std = @import("std");

const db = @import("./main.zig").db;
const zpass = @import("./zpass.zig");

const prompt = "zp: ";

pub const Repl = struct {
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,
    allocator: std.mem.Allocator,

    pub fn startRepl(self: @This()) !void {
        while (true) {
            try self.stdout.print(prompt, .{});
            const input = self.stdin.readUntilDelimiterAlloc(self.allocator, '\n', 64) catch {
                while (true) {
                    const extra = try self.stdin.readByte();
                    if (extra == '\n') break;
                }
                continue;
            };
            if (input.len > 64) continue;

            var iter = std.mem.splitSequence(u8, input, " ");

            var cmdBuf: [64]u8 = undefined;
            const cmd = std.ascii.lowerString(&cmdBuf, iter.first());

            var args = std.ArrayList([]const u8).init(self.allocator);
            while (iter.next()) |word| {
                if (std.mem.trim(u8, word, &std.ascii.whitespace).len == 0) continue;
                try args.append(word);
            }
            try self.handleCommand(cmd, args);
        }
    }

    // add, rm, ls, mv, edit, show
    // help
    fn handleCommand(self: @This(), cmd: []const u8, args: std.ArrayList([]const u8)) !void {
        if (args.items.len != 0) {
            for (args.items) |arg| {
                if (std.mem.trim(u8, arg, &std.ascii.whitespace).len == 0) continue;
            }
        }

        if (std.mem.eql(u8, cmd, "add")) {
            if (args.items.len == 0) {
                try self.stdout.print("need argument: <path>, but not provided\n", .{});
                return;
            }
            var account = zpass.Account{
                .data = std.StringHashMap([]const u8).init(self.allocator),
            };

            try account.data.put("path", args.items[0]);
            try self.stdout.print("password: ", .{});

            var attr = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch unreachable;
            const originalAttr = attr;

            attr.lflag.ECHO = false;
            attr.lflag.ICANON = false;
            std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, attr) catch unreachable;
            defer std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, originalAttr) catch unreachable;

            var pw: [256]u8 = undefined;

            //TODO: manage backspace correctly, eg stop at beginning of input, and actually delete from buffer
            var i: usize = 0;
            while (true) {
                const buf = self.stdin.readByte() catch break;
                if (buf == '\n') break;
                if (buf == 127) {
                    if (i > 0) {
                        try self.stdout.writeAll("\x08 \x08");
                        pw[i] = undefined;
                        i -= 1;
                    }
                } else {
                    try self.stdout.print("*", .{});
                    pw[i] = buf;
                    i += 1;
                }
            }
            try self.stdout.print("\n", .{});

            std.debug.print("pw: {s}\n", .{pw[0..i]});
            attr = originalAttr;
        }
    }
};
