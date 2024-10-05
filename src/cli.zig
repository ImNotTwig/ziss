const std = @import("std");

const main = @import("./main.zig");
const ziss = @import("./ziss.zig");

const prompt = "zs: ";

pub const Repl = struct {
    stdin: std.fs.File.Reader,
    stdout: std.fs.File.Writer,
    allocator: std.mem.Allocator,
    originalTermios: std.posix.termios = undefined,
    currentTermios: std.posix.termios = undefined,

    fn rawModeToggle(self: *@This()) !void {
        self.currentTermios.lflag.ICANON = !self.currentTermios.lflag.ICANON;
        if (self.currentTermios.lflag.ICANON == true) {
            std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, self.originalTermios) catch unreachable;
            return;
        }
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, self.currentTermios) catch unreachable;
    }

    pub fn startRepl(self: *@This()) !void {
        self.originalTermios = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch unreachable;
        self.currentTermios = self.originalTermios;
        while (true) {
            try self.stdout.print(prompt, .{});
            const input = self.stdin.readUntilDelimiterAlloc(self.allocator, '\n', 128) catch {
                try self.clearLineExtra();
                continue;
            };

            var iter = std.mem.splitSequence(u8, input, " ");

            var cmdBuf: [64]u8 = undefined;
            const cmd = std.ascii.lowerString(&cmdBuf, iter.first());

            var args = std.ArrayList([]const u8).init(self.allocator);
            defer args.deinit();
            while (iter.next()) |word| {
                if (std.mem.trim(u8, word, &std.ascii.whitespace).len == 0) continue;
                try args.append(word);
            }
            if (!try self.handleCommand(cmd, &args)) return;
        }
    }

    fn clearLineExtra(self: @This()) !void {
        while (true) {
            const extra = try self.stdin.readByte();
            if (extra == '\n') break;
        }
    }

    fn getConfirmation(self: *@This()) !bool {
        self.rawModeToggle() catch {};
        defer self.rawModeToggle() catch {};
        var confirm = false;
        while (true) {
            const buf = try self.stdin.readByte();
            if (std.ascii.toLower(buf) == 'n') {
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

    // add[x], rm[x], ls[x], mv[x], edit[x], show[x], search[ ]
    // help[ ]
    fn handleCommand(self: *@This(), cmd: []const u8, args: *std.ArrayList([]const u8)) !bool {
        if (args.items.len != 0) {
            for (args.items) |arg| {
                if (std.mem.trim(u8, arg, &std.ascii.whitespace).len == 0) continue;
            }
        }

        if (std.mem.eql(u8, cmd, "add")) {
            try self.add(args.*);
        }
        if (std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "rm")) {
            try self.rm(args.*);
        }
        if (std.mem.eql(u8, cmd, "list") or std.mem.eql(u8, cmd, "ls")) {
            try self.ls();
        }
        if (std.mem.eql(u8, cmd, "show") or std.mem.eql(u8, cmd, "cat")) {
            try self.show(args.*);
        }
        if (std.mem.eql(u8, cmd, "move") or std.mem.eql(u8, cmd, "mv")) {
            try self.mv(args);
        }
        if (std.mem.eql(u8, cmd, "edit") or std.mem.eql(u8, cmd, "ed")) {
            try self.ed(args.*);
        }

        return true;
    }

    fn ed(self: *@This(), args: std.ArrayList([]const u8)) !void {
        if (args.items.len == 0) {
            try self.stdout.print("need argument: <path>, but not provided\n", .{});
            return;
        }
        for (0.., main.db.accounts.items) |i, v| {
            if (std.mem.eql(u8, v.data.get("path").?, args.items[0])) {
                while (true) {
                    var iter = v.data.iterator();
                    while (iter.next()) |j| {
                        if (std.mem.eql(u8, j.key_ptr.*, "path")) continue;
                        try self.stdout.print("{s}={s}\n", .{ j.key_ptr.*, j.value_ptr.* });
                    }
                    try self.stdout.print("Does this look correct? [y/N] ", .{});
                    if (try self.getConfirmation()) break;
                    try self.readFields(&main.db.accounts.items[i]);
                }
                try main.db.writeDBToFile();
                try self.stdout.print("Wrote {s} to file.\n", .{v.data.get("path").?});
                return;
            }
        }
    }

    fn mv(self: @This(), args: *std.ArrayList([]const u8)) !void {
        if (args.items.len < 2) {
            try self.stdout.print("need argument(s): <source, destination>, but not provided\n", .{});
            return;
        }

        var account: ziss.Account = undefined;
        var found = false;
        for (0.., main.db.accounts.items) |i, j| {
            if (std.mem.eql(u8, args.items[0], j.data.get("path").?)) {
                const hashOut = try ziss.hash(args.items[0], self.allocator);
                const path = try std.mem.concat(self.allocator, u8, &.{ main.db.config.root, "/", hashOut });
                try std.fs.deleteFileAbsolute(path);
                account = main.db.accounts.swapRemove(i);
                found = true;
                break;
            }
        }
        if (!found) {
            try self.stdout.print("Could not find {s} in store.", .{args.items[0]});
            return;
        }

        try account.data.put("path", args.items[1]);
        try main.db.addAccount(account);
        try self.stdout.print("moved: {s} to {s}\n", .{ args.items[0], args.items[1] });
        try main.db.writeDBToFile();
    }

    fn show(self: @This(), args: std.ArrayList([]const u8)) !void {
        if (args.items.len == 0) {
            try self.stdout.print("need argument: <path>, but not provided\n", .{});
            return;
        }

        for (main.db.accounts.items) |account| {
            if (std.mem.eql(u8, account.data.get("path").?, args.items[0])) {
                var iter = account.data.iterator();
                while (iter.next()) |i| {
                    if (args.items.len == 2 and std.mem.eql(u8, args.items[1], i.key_ptr.*)) {
                        try self.stdout.print("{s}={s}\n", .{ i.key_ptr.*, i.value_ptr.* });
                        return;
                    } else {
                        if (std.mem.eql(u8, i.key_ptr.*, "path")) continue;
                        try self.stdout.print("{s}={s}\n", .{ i.key_ptr.*, i.value_ptr.* });
                    }
                }
                return;
            }
        }
    }

    fn ls(self: @This()) !void {
        for (main.db.accounts.items) |account| {
            try self.stdout.print("{s}\n", .{account.data.get("path").?});
        }
    }

    fn rm(self: @This(), args: std.ArrayList([]const u8)) !void {
        if (args.items.len == 0) {
            try self.stdout.print("need argument: <path>, but not provided\n", .{});
            return;
        }
        for (0.., main.db.accounts.items) |i, v| {
            if (std.mem.eql(u8, args.items[0], v.data.get("path").?)) {
                _ = main.db.accounts.swapRemove(i);
                const hashOut = try ziss.hash(v.data.get("path").?, self.allocator);
                const path = try std.mem.concat(self.allocator, u8, &.{ main.db.config.root, "/", hashOut });
                try self.stdout.print("removed: {s}\n", .{path});
                std.fs.deleteFileAbsolute(path) catch {};
                return;
            }
        }
        try self.stdout.print("Could not find: {s}\n", .{args.items[0]});
    }

    fn add(self: *@This(), args: std.ArrayList([]const u8)) !void {
        for (main.db.accounts.items) |i| {
            if (std.mem.eql(u8, i.data.get("path").?, args.items[0])) {
                try self.stdout.print(
                    "{s} already exists, would you like to overwrite? [y/N] ",
                    .{args.items[0]},
                );
                if (!try self.getConfirmation()) return;
            }
        }

        if (args.items.len == 0) {
            try self.stdout.print("need argument: <path>, but not provided\n", .{});
            return;
        }
        var account = ziss.Account{
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
        } else {
            try main.db.addAccount(account);
            try main.db.writeDBToFile();
            return;
        }
        var iter = account.data.iterator();

        //TODO: Add option to edit password
        var confirmed = false;
        while (true) {
            while (iter.next()) |i| {
                if (std.mem.eql(u8, i.key_ptr.*, "password")) continue;
                if (std.mem.eql(u8, i.key_ptr.*, "path")) continue;
                try self.stdout.print("{s}={s}\n", .{ i.key_ptr.*, i.value_ptr.* });
            }
            try self.stdout.print("Is this correct? [y/N] ", .{});
            confirmed = try self.getConfirmation();
            if (confirmed) break;

            var fieldBuf: [256]u8 = undefined;
            var valueBuf: [256]u8 = undefined;

            try self.stdout.print("Field to edit: ", .{});
            const field = std.ascii.lowerString(&fieldBuf, try self.stdin.readUntilDelimiterAlloc(self.allocator, '\n', 256));
            if (std.mem.eql(u8, "", std.mem.trim(u8, field, &std.ascii.whitespace))) break;

            try self.stdout.print("value: ", .{});
            const value = std.ascii.lowerString(&valueBuf, try self.stdin.readUntilDelimiterAlloc(self.allocator, '\n', 256));

            try account.data.put(field, value);
        }

        try main.db.addAccount(account);
        try main.db.writeDBToFile();
    }

    fn readFields(self: @This(), account: *ziss.Account) !void {
        //NOTE: perhaps make a configuration option for default fields?
        var lookForField = true;
        var field: []u8 = undefined;
        var value: []u8 = undefined;
        try self.stdout.print("field (leave empty to continue): ", .{});
        while (true) {
            var lowerBuf: [256]u8 = undefined;
            const input = try self.stdin.readUntilDelimiterAlloc(self.allocator, '\n', 256);
            if (lookForField) {
                const lower = std.ascii.lowerString(&lowerBuf, input);
                if (std.mem.eql(u8, "", std.mem.trim(u8, lower, &std.ascii.whitespace))) break;
                field = input;
                try self.stdout.print("value: ", .{});
            } else {
                value = input;
                try account.data.put(field, value);
                try self.stdout.print("field (leave empty to continue): ", .{});
            }
            lookForField = !lookForField;
        }
        try self.stdout.print("\n", .{});
    }

    fn readPassword(self: *@This(), prevPass: ?[256]u8) ![]u8 {
        try self.stdout.print("password: ", .{});
        self.currentTermios.lflag.ECHO = !self.currentTermios.lflag.ECHO;
        self.rawModeToggle() catch {};
        defer {
            self.currentTermios.lflag.ECHO = !self.currentTermios.lflag.ECHO;
            self.rawModeToggle() catch {};
        }

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
