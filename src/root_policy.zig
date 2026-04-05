const std = @import("std");
const platform_paths = @import("platform_paths.zig");

fn isExactOrChild(path: []const u8, prefix: []const u8) bool {
    return platform_paths.isExactOrChildPath(path, prefix);
}

fn isWindowsDriveRoot(path: []const u8) bool {
    if (path.len != 3) return false;
    const c = path[0];
    const is_alpha = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
    return is_alpha and path[1] == ':' and (path[2] == '/' or path[2] == '\\');
}

fn hasPathSegment(path: []const u8, segment: []const u8) bool {
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, segment)) return true;
    }
    return false;
}

pub fn isIndexableRoot(path: []const u8) bool {
    if (path.len == 0) return false;
    var norm_buf: [std.fs.max_path_bytes]u8 = undefined;
    const norm = platform_paths.normalizeLower(path, &norm_buf);
    if (isWindowsDriveRoot(norm)) return false;
    if (std.mem.startsWith(u8, norm, "//")) return false;
    if (hasPathSegment(norm, "appdata") and hasPathSegment(norm, "local") and hasPathSegment(norm, "temp")) return false;
    if (hasPathSegment(norm, "windows") and hasPathSegment(norm, "temp")) return false;

    if (std.mem.eql(u8, norm, "/")) return false;
    if (isExactOrChild(norm, "/private/tmp")) return false;
    if (isExactOrChild(norm, "/tmp")) return false;
    if (isExactOrChild(norm, "/var/tmp")) return false;
    return true;
}

const testing = std.testing;

test "issue-80: root / is denied" {
    try testing.expect(!isIndexableRoot("/"));
}

test "issue-80: empty path is denied" {
    try testing.expect(!isIndexableRoot(""));
}

test "issue-80: /tmp is denied" {
    try testing.expect(!isIndexableRoot("/tmp"));
    try testing.expect(!isIndexableRoot("/tmp/foo"));
}

test "issue-80: normal paths are allowed" {
    try testing.expect(isIndexableRoot("/Users/dev/project"));
    try testing.expect(isIndexableRoot("/home/user/code"));
}

test "issue-91: windows temp roots are denied" {
    try testing.expect(!isIndexableRoot("C:/Users/dev/AppData/Local/Temp/repo"));
    try testing.expect(!isIndexableRoot("c:\\users\\dev\\appdata\\local\\temp\\repo"));
}
