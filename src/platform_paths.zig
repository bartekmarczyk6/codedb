const std = @import("std");
const builtin = @import("builtin");

fn isAlpha(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

fn isSep(c: u8) bool {
    return c == '/' or c == '\\';
}

fn hasDrivePrefix(path: []const u8) bool {
    return path.len >= 2 and isAlpha(path[0]) and path[1] == ':';
}

fn isAbsolute(path: []const u8) bool {
    if (path.len == 0) return false;
    if (isSep(path[0])) return true;
    return hasDrivePrefix(path);
}

pub fn isPathSafe(path: []const u8) bool {
    if (path.len == 0) return false;
    if (isAbsolute(path)) return false;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;

    var saw_component = false;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= path.len) : (i += 1) {
        if (i != path.len and !isSep(path[i])) continue;
        const component = path[start..i];
        if (component.len == 0) return false;
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
        if (std.mem.indexOfScalar(u8, component, ':') != null) return false;
        saw_component = true;
        start = i + 1;
    }
    return saw_component;
}

pub fn normalizeRelativePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!isPathSafe(path)) return error.InvalidPath;
    const out = try allocator.alloc(u8, path.len);
    for (path, 0..) |c, i| {
        out[i] = if (c == '\\') '/' else c;
    }
    return out;
}

pub fn normalizeLower(path: []const u8, buf: *[std.fs.max_path_bytes]u8) []const u8 {
    if (path.len > buf.len) return path;
    for (path, 0..) |c, i| {
        const mapped = if (c == '\\') '/' else c;
        buf[i] = std.ascii.toLower(mapped);
    }
    return buf[0..path.len];
}

pub fn isExactOrChildPath(path: []const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    return path.len == prefix.len or path[prefix.len] == '/';
}

pub fn getBaseDataDir(allocator: std.mem.Allocator, abs_root: []const u8) ![]u8 {
    if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "LOCALAPPDATA")) |local| {
            defer allocator.free(local);
            return std.fmt.allocPrint(allocator, "{s}/codedb", .{local});
        } else |_| {}
        if (std.process.getEnvVarOwned(allocator, "APPDATA")) |app| {
            defer allocator.free(app);
            return std.fmt.allocPrint(allocator, "{s}/codedb", .{app});
        } else |_| {}
        if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |profile| {
            defer allocator.free(profile);
            return std.fmt.allocPrint(allocator, "{s}/AppData/Local/codedb", .{profile});
        } else |_| {}
        return std.fmt.allocPrint(allocator, "{s}/.codedb", .{abs_root});
    }

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fmt.allocPrint(allocator, "{s}/.codedb", .{home});
    } else |_| {
        return std.fmt.allocPrint(allocator, "{s}/.codedb", .{abs_root});
    }
}

pub fn getProjectsDir(allocator: std.mem.Allocator, abs_root: []const u8) ![]u8 {
    const base = try getBaseDataDir(allocator, abs_root);
    defer allocator.free(base);
    return std.fmt.allocPrint(allocator, "{s}/projects", .{base});
}

pub fn getProjectDataDir(allocator: std.mem.Allocator, abs_root: []const u8) ![]u8 {
    const hash = std.hash.Wyhash.hash(0, abs_root);
    const projects_dir = try getProjectsDir(allocator, abs_root);
    defer allocator.free(projects_dir);
    return std.fmt.allocPrint(allocator, "{s}/{x}", .{ projects_dir, hash });
}

pub fn getCentralSnapshotPath(allocator: std.mem.Allocator, abs_root: []const u8) ![]u8 {
    const data_dir = try getProjectDataDir(allocator, abs_root);
    defer allocator.free(data_dir);
    return std.fmt.allocPrint(allocator, "{s}/codedb.snapshot", .{data_dir});
}

const testing = std.testing;

test "issue-91: path safety rejects absolute/traversal/windows forms" {
    try testing.expect(!isPathSafe(""));
    try testing.expect(!isPathSafe("/etc/passwd"));
    try testing.expect(!isPathSafe("C:/Windows/System32"));
    try testing.expect(!isPathSafe("C:\\Windows\\System32"));
    try testing.expect(!isPathSafe("\\\\server\\share"));
    try testing.expect(!isPathSafe("../secret"));
    try testing.expect(!isPathSafe("foo/../bar"));
    try testing.expect(!isPathSafe("foo\\..\\bar"));
    try testing.expect(!isPathSafe("foo/./bar"));
    try testing.expect(!isPathSafe("foo//bar"));
    try testing.expect(isPathSafe("src/main.zig"));
    try testing.expect(isPathSafe("src\\main.zig"));
}

test "issue-91: normalizeRelativePath converts backslashes" {
    const p = try normalizeRelativePath(testing.allocator, "a\\b\\c.txt");
    defer testing.allocator.free(p);
    try testing.expectEqualStrings("a/b/c.txt", p);
}
