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
                try self.clearLineExtra();
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

    fn clearLineExtra(self: @This()) !void {
        while (true) {
            const extra = try self.stdin.readByte();
            if (extra == '\n') break;
        }
    }

    fn getConfirmation(self: @This()) !bool {
        var attr = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch unreachable;
        const originalAttr = attr;

        attr.lflag.ECHO = true;
        attr.lflag.ICANON = false;
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, attr) catch unreachable;
        defer std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, originalAttr) catch unreachable;

        var confirm = false;
        while (true) {
            const buf = try self.stdin.readByte();
            if (std.ascii.toLower(buf) == 'n') {
                std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, originalAttr) catch unreachable;
                break;
            }
            if (std.ascii.toLower(buf) == 'y') {
                confirm = true;
                break;
            }
        }
        try self.stdout.print("\n", .{});
        return confirm;
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
        for (main.db.accounts.items) |i| {
            if (std.mem.eql(u8, i.data.get("path").?, args.items[0])) {
                try self.stdout.print(
                    "{s} already exists, would you like to overwrite?",
                    .{args.items[0]},
                );
            }
        }
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
            pw = try self.readPassword(null);
        }
        try account.data.put("password", pw);

        try self.stdout.print("Would you like to add any additional fields? [y/N] ", .{});
        if (try self.getConfirmation()) {
            try self.readFields(&account);
        }

        try main.db.accounts.append(account);
        try main.db.writeDBToFile();
    }

    fn readFields(self: @This(), account: *zpass.Account) !void {
        //TODO: ask user for confirmation at end of adding fields
        //NOTE: perhaps make a configuration option for default fields?
        var lookForField = true;
        var field: []u8 = undefined;
        var value: []u8 = undefined;
        try self.stdout.print("field (leave empty to continue): ", .{});
        while (true) {
            const buf = try self.stdin.readUntilDelimiterAlloc(self.allocator, '\n', 64);
            if (lookForField) {
                if (std.mem.eql(u8, "", std.mem.trim(u8, buf, &std.ascii.whitespace))) break;
                field = buf;
                try self.stdout.print("value: ", .{});
            } else {
                value = buf;
                try account.data.put(field, value);
                try self.stdout.print("field (leave empty to continue): ", .{});
            }
            lookForField = !lookForField;
        }
        try self.stdout.print("\n", .{});
    }

    fn readPassword(self: @This(), prevPass: ?[256]u8) ![]u8 {
        try self.stdout.print("password: ", .{});
        var attr = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch unreachable;
        const originalAttr = attr;

        attr.lflag.ECHO = false;
        attr.lflag.ICANON = false;
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, attr) catch unreachable;
        defer std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, originalAttr) catch unreachable;

        var pw: [256]u8 = if (prevPass) |p| p else undefined;
        var len: usize = if (prevPass) |p| p.len else 0;

        var visible = false;
        while (true) {
            const buf = try self.stdin.readByte();
            if (buf == '\n') break;
            if (buf == '\t') {
                visible = !visible;
                for (0..len) |_| {
                    try self.stdout.writeAll("\x08 \x08");
                }
                for (0..len) |j| {
                    const c = if (visible) pw[j] else '*';
                    try self.stdout.print("{c}", .{c});
                }
            } else if (buf == std.ascii.control_code.del) {
                if (len > 0) {
                    try self.stdout.writeAll("\x08 \x08");
                    pw[len] = undefined;
                    len -= 1;
                }
            } else {
                if (len >= pw.len) continue;
                if (!visible) {
                    try self.stdout.print("*", .{});
                } else {
                    try self.stdout.print("{c}", .{buf});
                }

                pw[len] = buf;
                len += 1;
            }
        }
        try self.stdout.print("\n", .{});

        return self.allocator.dupe(u8, pw[0..len]);
    }
};
