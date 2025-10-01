const std = @import("std");
const process = std.process;
const fs = std.fs;
const mem = std.mem;

const Config = struct {
    steps: []Step,
};

const Step = struct {
    name: ?[]const u8 = null,
    selection: ?[]const u8 = null,
    command: []const u8,
    args: ?[][]const u8 = null,
    options: ?[]Option = null,
    default: ?[]const u8 = null,
};

const Option = struct {
    name: []const u8,
    args: ?[][]const u8 = null,
    default: ?bool = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get HOME directory
    const home = std.posix.getenv("HOME") orelse {
        std.debug.print("Error: HOME environment variable not set\n", .{});
        return error.HomeNotSet;
    };

    // Build path to config file
    const config_path = try fs.path.join(allocator, &[_][]const u8{ home, ".ccinit.json" });
    defer allocator.free(config_path);

    // Read config file
    const config_file = try fs.cwd().openFile(config_path, .{});
    defer config_file.close();

    const config_content = try config_file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(config_content);

    // Parse JSON
    const parsed = try std.json.parseFromSlice(Config, allocator, config_content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const config = parsed.value;

    // Process each step
    for (config.steps) |step| {
        if (step.name) |name| {
            // Simple y/n prompt
            try handleSimpleStep(allocator, step, name);
        } else if (step.selection) |selection| {
            // Checkbox selection
            try handleSelectionStep(allocator, step, selection);
        }
    }
}

fn handleSimpleStep(allocator: mem.Allocator, step: Step, name: []const u8) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    const should_execute = while (true) {
        // Display prompt with default indicator
        try stdout.print("{s}? ", .{name});
        if (step.default) |default| {
            if (mem.eql(u8, default, "y") or mem.eql(u8, default, "Y")) {
                try stdout.writeAll("(Y/n) ");
            } else if (mem.eql(u8, default, "n") or mem.eql(u8, default, "N")) {
                try stdout.writeAll("(y/N) ");
            } else {
                try stdout.writeAll("(y/n) ");
            }
        } else {
            try stdout.writeAll("(y/n) ");
        }

        // Read user input
        var buf: [10]u8 = undefined;
        const input = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse "";
        const trimmed = mem.trim(u8, input, &std.ascii.whitespace);

        // Determine if we should execute
        if (trimmed.len == 0) {
            // Empty input - use default if available, otherwise require valid input
            if (step.default) |default| {
                break mem.eql(u8, default, "y") or mem.eql(u8, default, "Y");
            } else {
                try stdout.writeAll("Please choose y or n\n");
                continue;
            }
        }

        // Check for valid y/n input
        if (mem.eql(u8, trimmed, "y") or mem.eql(u8, trimmed, "Y")) {
            break true;
        } else if (mem.eql(u8, trimmed, "n") or mem.eql(u8, trimmed, "N")) {
            break false;
        } else {
            try stdout.writeAll("Please choose y or n\n");
            continue;
        }
    };

    if (should_execute) {
        try executeCommand(allocator, step.command, step.args);
    }
}

fn handleSelectionStep(allocator: mem.Allocator, step: Step, selection_text: []const u8) !void {
    const options = step.options orelse return;
    if (options.len == 0) return;

    // Initialize selection state - defaults based on option.default
    const selected = try allocator.alloc(bool, options.len);
    defer allocator.free(selected);

    for (options, 0..) |option, i| {
        selected[i] = option.default orelse false;
    }

    // Display and handle checkbox UI
    try displayCheckboxes(selection_text, options, selected);
    var current_pos: usize = 0;

    // Enable raw mode for terminal
    const original_termios = try enableRawMode();
    defer disableRawMode(original_termios) catch {};

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut().writer();

    while (true) {
        var buf: [3]u8 = undefined;
        const bytes_read = try stdin.read(&buf);
        if (bytes_read == 0) continue;

        // Handle Enter key
        if (buf[0] == '\r' or buf[0] == '\n') {
            try stdout.writeAll("\n");
            break;
        }

        // Handle space key (toggle)
        if (buf[0] == ' ') {
            selected[current_pos] = !selected[current_pos];
            try redrawCheckboxes(stdout, options, selected, current_pos);
            continue;
        }

        // Handle arrow keys
        if (bytes_read == 3 and buf[0] == 27 and buf[1] == '[') {
            if (buf[2] == 'A') { // Up arrow
                if (current_pos > 0) {
                    current_pos -= 1;
                    try redrawCheckboxes(stdout, options, selected, current_pos);
                }
            } else if (buf[2] == 'B') { // Down arrow
                if (current_pos < options.len - 1) {
                    current_pos += 1;
                    try redrawCheckboxes(stdout, options, selected, current_pos);
                }
            }
        }
    }

    // Execute selected options
    for (options, 0..) |option, i| {
        if (selected[i]) {
            // Build combined args: step.args + option.args
            const combined_args = try buildCombinedArgs(allocator, step.args, option.args);
            defer allocator.free(combined_args);

            try executeCommand(allocator, step.command, combined_args);
        }
    }
}

fn buildCombinedArgs(allocator: mem.Allocator, base_args: ?[][]const u8, option_args: ?[][]const u8) ![][]const u8 {
    const base_len = if (base_args) |args| args.len else 0;
    const option_len = if (option_args) |args| args.len else 0;

    const combined = try allocator.alloc([]const u8, base_len + option_len);

    var idx: usize = 0;
    if (base_args) |args| {
        for (args) |arg| {
            combined[idx] = arg;
            idx += 1;
        }
    }
    if (option_args) |args| {
        for (args) |arg| {
            combined[idx] = arg;
            idx += 1;
        }
    }

    return combined;
}

fn displayCheckboxes(selection_text: []const u8, options: []const Option, selected: []const bool) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}\n", .{selection_text});

    for (options, 0..) |option, i| {
        const checkbox = if (selected[i]) "[x]" else "[ ]";
        const cursor = if (i == 0) ">" else " ";
        try stdout.print("{s} {s} {s}\n", .{ cursor, checkbox, option.name });
    }
}

fn redrawCheckboxes(stdout: anytype, options: []const Option, selected: []const bool, current_pos: usize) !void {
    // Move cursor up to redraw
    try stdout.print("\x1b[{d}A\r", .{options.len});

    for (options, 0..) |option, i| {
        const checkbox = if (selected[i]) "[x]" else "[ ]";
        const cursor = if (i == current_pos) ">" else " ";
        try stdout.print("{s} {s} {s}\x1b[K\n", .{ cursor, checkbox, option.name });
    }
}

const termios = if (@hasDecl(std.posix.system, "termios")) std.posix.system.termios else std.c.termios;

fn enableRawMode() !termios {
    const stdin_fd = std.io.getStdIn().handle;

    var raw = try std.posix.tcgetattr(stdin_fd);
    const original = raw;

    // Disable canonical mode and echo
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;

    try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);

    return original;
}

fn disableRawMode(original: termios) !void {
    const stdin_fd = std.io.getStdIn().handle;
    try std.posix.tcsetattr(stdin_fd, .FLUSH, original);
}

fn executeCommand(allocator: mem.Allocator, command: []const u8, args: ?[][]const u8) !void {
    // Substitute environment variables in command
    const expanded_command = try expandEnvVars(allocator, command);
    defer allocator.free(expanded_command);

    // Build argv array
    const arg_count = 1 + (if (args) |a| a.len else 0);
    const argv = try allocator.alloc([]const u8, arg_count);
    defer allocator.free(argv);

    argv[0] = expanded_command;
    if (args) |a| {
        for (a, 0..) |arg, i| {
            const expanded_arg = try expandEnvVars(allocator, arg);
            argv[i + 1] = expanded_arg;
        }
    }
    defer {
        if (args) |_| {
            for (argv[1..]) |arg| {
                allocator.free(arg);
            }
        }
    }

    // Execute with inherited stdio
    var child = process.Child.init(argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Command exited with code: {}\n", .{code});
            }
        },
        .Signal => |sig| {
            std.debug.print("Command terminated by signal: {}\n", .{sig});
        },
        else => {},
    }
}

fn expandEnvVars(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        // Handle ${VAR} syntax
        if (i + 1 < input.len and input[i] == '$' and input[i + 1] == '{') {
            // Find closing brace
            const start = i + 2;
            var end = start;
            while (end < input.len and input[end] != '}') : (end += 1) {}

            if (end < input.len) {
                const var_name = input[start..end];
                if (std.posix.getenv(var_name)) |value| {
                    try result.appendSlice(value);
                }
                i = end + 1;
                continue;
            }
        }

        // Handle $(command) syntax
        if (i + 1 < input.len and input[i] == '$' and input[i + 1] == '(') {
            // Find closing paren
            const start = i + 2;
            var end = start;
            while (end < input.len and input[end] != ')') : (end += 1) {}

            if (end < input.len) {
                const cmd = input[start..end];
                // Execute command and capture output
                const output = try executeAndCapture(allocator, cmd);
                defer allocator.free(output);
                // Trim trailing newline
                const trimmed = mem.trimRight(u8, output, &std.ascii.whitespace);
                try result.appendSlice(trimmed);
                i = end + 1;
                continue;
            }
        }

        try result.append(input[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

fn executeAndCapture(allocator: mem.Allocator, cmd: []const u8) ![]const u8 {
    // Parse command and args (simple space splitting)
    var argv_list = std.ArrayList([]const u8).init(allocator);
    defer argv_list.deinit();

    var iter = mem.tokenizeScalar(u8, cmd, ' ');
    while (iter.next()) |token| {
        try argv_list.append(token);
    }

    if (argv_list.items.len == 0) return try allocator.dupe(u8, "");

    // Execute and capture stdout
    var child = process.Child.init(argv_list.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout_data = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    _ = try child.wait();

    return stdout_data;
}
