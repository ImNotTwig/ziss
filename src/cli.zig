const std = @import("std");

const main = @import("./main.zig");
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
                // clear standard input buffer
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
            defer args.deinit();
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
            try self.add(args);
        }
    }

    fn add(self: @This(), args: std.ArrayList([]const u8)) !void {
        if (args.items.len == 0) {
            try self.stdout.print("need argument: <path>, but not provided\n", .{});
            return;
        }
        var account = zpass.Account{
            .data = std.StringHashMap([]const u8).init(self.allocator),
        };

        try account.data.put("path", args.items[0]);

        var pw: []u8 = "";
        while (std.mem.eql(u8, "", std.mem.trim(u8, pw, &std.ascii.whitespace))) {
            pw = try self.readPassword();
        }
        try account.data.put("password", pw);

        try self.stdout.print("Would you like to add any additional fields? Recommended: username, email, service (y/N) ", .{});
        while (true) {
            const buf = try self.stdin.readByte();
            if (std.ascii.toLower(buf) == 'n') {
                try main.db.accounts.append(account);
                try main.db.writeDBToFile();
                return;
            }
            if (std.ascii.toLower(buf) == 'y') {
                _ = try self.stdin.readByte();
                break;
            }
        }
        //TODO: ask user for confirmation at end of adding fields
        //NOTE: perhaps make a configuration option for default fields?
        var lookForField = true;
        var field: []u8 = undefined;
        var value: []u8 = undefined;
        try self.stdout.print("field (leave empty to continue): ", .{});
        while (true) {
            const buf = try self.stdin.readUntilDelimiterAlloc(self.allocator, '\n', 64);
            if (lookForField) {
                if (std.mem.eql(u8, "", std.mem.trim(u8, buf, &std.ascii.whitespace))) {
                    try main.db.accounts.append(account);
                    try main.db.writeDBToFile();
                    return;
                }
                field = buf;
                try self.stdout.print("value: ", .{});
            } else {
                value = buf;
                try account.data.put(field, value);
                try self.stdout.print("field (leave empty to continue): ", .{});
            }
            lookForField = !lookForField;
        }
    }

    fn readPassword(self: @This()) ![]u8 {
        try self.stdout.print("password: ", .{});
        var attr = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch unreachable;
        const originalAttr = attr;

        attr.lflag.ECHO = false;
        attr.lflag.ICANON = false;
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, attr) catch unreachable;

        var pw: [256]u8 = undefined;

        var i: usize = 0;
        while (true) {
            const buf = try self.stdin.readByte();
            if (buf == '\n') break;
            if (buf == std.ascii.control_code.del) {
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

        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, originalAttr) catch unreachable;
        return self.allocator.dupe(u8, pw[0..i]);
    }
};
