const std = @import("std");

pub fn clearLineExtra(stdin: std.fs.File.Reader) !void {
    while (true) {
        const extra = try stdin.readByte();
        if (extra == '\n') break;
    }
}

pub fn rawModeToggle(curTermios: *std.posix.termios, orgTermios: *std.posix.termios) !void {
    curTermios.lflag.ICANON = !curTermios.lflag.ICANON;
    if (curTermios.lflag.ICANON == true) {
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, orgTermios.*) catch unreachable;
        return;
    }
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, curTermios.*) catch unreachable;
}

pub fn getConfirmation(stdin: std.fs.File.Reader, stdout: std.fs.File.Writer, curTermios: *std.posix.termios, orgTermios: *std.posix.termios) !bool {
    rawModeToggle(curTermios, orgTermios) catch {};
    defer rawModeToggle(curTermios, orgTermios) catch {};
    var confirm = false;
    while (true) {
        const buf = try stdin.readByte();
        if (std.ascii.toLower(buf) == 'n') {
            break;
        }
        if (std.ascii.toLower(buf) == 'y') {
            confirm = true;
            break;
        }
    }
    try stdout.print("\n", .{});
    return confirm;
}
