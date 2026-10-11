//! M17 helper allow-list and reply encoding (docs/ROADMAP.md, ADR-046).
//! Pure fixed-storage parsing: no allocator, shell expansion or syscalls.
//!
//! Reference note: none of these acceptance tests has been validated against
//! a reference implementation yet; the M17 implementation does not exist yet.
const std = @import("std");
const testing = std.testing;
const milestone = @import("milestone.zig");

pub const max_helpers = 32;
/// Maximum bytes per allow-list line, excluding its trailing newline.
pub const max_line_len = 1024;

/// Owned storage: names and paths use their explicit lengths. Arguments are
/// packed as NUL-terminated strings in args[0..args_len], with argc entries;
/// the executable path is separate, not included in argc.
pub const Helper = struct {
    name: [32]u8 = undefined,
    name_len: usize = 0,
    uid: u32 = 0,
    gid: u32 = 0,
    path: [max_line_len]u8 = undefined,
    path_len: usize = 0,
    args: [max_line_len]u8 = undefined,
    args_len: usize = 0,
    argc: usize = 0,
};

pub const AllowList = struct {
    helpers: [max_helpers]Helper = undefined,
    len: usize = 0,
};

pub const ParseError = error{ Invalid, DuplicateName, TooManyHelpers, TooLong };

/// Parses `<name> <uid>:<gid> <absolute path> [args...]` into owned storage.
/// Blank lines and # comment lines are ignored. Names are [a-z0-9-]{1,32};
/// uid/gid follow decimal.parseU32, including zero and the u32 upper boundary.
/// An invalid list must not be used, even if some preceding entries parsed.
pub fn parseAllowList(text: []const u8, out: *AllowList) ParseError!void {
    _ = text;
    _ = out;
    @panic("TODO(M17)");
}

/// Looks up an exact helper name; an absent name returns null.
pub fn lookup(list: *const AllowList, name: []const u8) ?*const Helper {
    _ = list;
    _ = name;
    @panic("TODO(M17)");
}

/// Encodes a validated name and a positive pid, or null for REFUSED, including
/// exactly one trailing newline. Returns the written portion of caller storage.
pub fn encodeReply(name: []const u8, pid: ?u32, buf: []u8) error{NoSpaceLeft}![]u8 {
    _ = name;
    _ = pid;
    _ = buf;
    @panic("TODO(M17)");
}

test "helpers: comments, blank lines, identities, paths and arguments are preserved" {
    try milestone.require(17);
    var list: AllowList = .{};
    try parseAllowList(
        "# image-declared helpers\n\n" ++
            "initdb 1001:1002 /system/bin/initdb -D /priv/postgres\n" ++
            "\n# another helper\n" ++
            "console-handover 0:0 /system/bin/handover\n",
        &list,
    );
    try testing.expectEqual(@as(usize, 2), list.len);
    const helper = lookup(&list, "initdb") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("initdb", helper.name[0..helper.name_len]);
    try testing.expectEqual(@as(u32, 1001), helper.uid);
    try testing.expectEqual(@as(u32, 1002), helper.gid);
    try testing.expectEqualStrings("/system/bin/initdb", helper.path[0..helper.path_len]);
    try testing.expectEqual(@as(usize, 2), helper.argc);
    try testing.expectEqualStrings("-D\x00/priv/postgres\x00", helper.args[0..helper.args_len]);
    const root = lookup(&list, "console-handover") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 0), root.uid);
    try testing.expectEqual(@as(u32, 0), root.gid);
    try testing.expectEqual(@as(usize, 0), root.argc);
    try testing.expectEqual(@as(usize, 0), root.args_len);
}

test "helpers: empty lists and absent or partial names do not match" {
    try milestone.require(17);
    var list: AllowList = .{};
    try parseAllowList("\n# no helpers\n\n", &list);
    try testing.expectEqual(@as(usize, 0), list.len);
    try testing.expect(lookup(&list, "initdb") == null);
    try parseAllowList("initdb 0:0 /system/bin/initdb", &list);
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expect(lookup(&list, "no-such-helper") == null);
    try testing.expect(lookup(&list, "init") == null);
    try testing.expect(lookup(&list, "INITDB") == null);
}

test "helpers: maximum-length names and canonical u32 identities are accepted" {
    try milestone.require(17);
    var list: AllowList = .{};
    const name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try parseAllowList(name ++ " 4294967295:4294967295 /helper\n- 0:0 /root", &list);
    try testing.expectEqual(@as(usize, 2), list.len);
    const helper = lookup(&list, name) orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings(name, helper.name[0..helper.name_len]);
    try testing.expectEqual(std.math.maxInt(u32), helper.uid);
    try testing.expectEqual(std.math.maxInt(u32), helper.gid);
    const root = lookup(&list, "-") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("/root", root.path[0..root.path_len]);
}

test "helpers: malformed records, names and relative paths are rejected" {
    try milestone.require(17);
    const rejected = [_][]const u8{
        " 0:0 /helper",
        "two words 0:0 /helper",
        "initdb",
        "initdb 0:0",
        "initdb 0 /helper",
        "initdb 0: /helper",
        "initdb :0 /helper",
        "initdb 0:0:0 /helper",
        "UPPER 0:0 /helper",
        ". 0:0 /helper",
        ".. 0:0 /helper",
        "a/b 0:0 /helper",
        "a.b 0:0 /helper",
        "é 0:0 /helper",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0:0 /helper",
        "initdb 0:0 relative/path",
        "initdb 0:0 ./helper",
        "initdb 0:0 ../helper",
    };
    for (rejected) |text| {
        var list: AllowList = .{};
        try testing.expectError(error.Invalid, parseAllowList(text, &list));
    }
}

test "helpers: uid and gid reject non-canonical decimals and u32 overflow" {
    try milestone.require(17);
    const rejected = [_][]const u8{ "00", "01", "+1", "-1", "1.0", "0x1", "١", "4294967296", "99999999999" };
    for (rejected) |number| {
        var buf: [128]u8 = undefined;
        var list: AllowList = .{};
        const bad_uid = try std.fmt.bufPrint(&buf, "initdb {s}:0 /helper", .{number});
        try testing.expectError(error.Invalid, parseAllowList(bad_uid, &list));
        const bad_gid = try std.fmt.bufPrint(&buf, "initdb 0:{s} /helper", .{number});
        try testing.expectError(error.Invalid, parseAllowList(bad_gid, &list));
    }
}

test "helpers: duplicate names are rejected even with different identities and paths" {
    try milestone.require(17);
    var list: AllowList = .{};
    try testing.expectError(error.DuplicateName, parseAllowList(
        "initdb 0:0 /first\ninitdb 1000:1000 /second -D /priv/db\n",
        &list,
    ));
}

test "helpers: exactly max_helpers entries fit and the next entry is rejected" {
    try milestone.require(17);
    var text: [max_helpers * 64 + 64]u8 = undefined;
    var len: usize = 0;
    for (0..max_helpers) |i| {
        const line = try std.fmt.bufPrint(text[len..], "h{d} 0:0 /helper\n", .{i});
        len += line.len;
    }
    var list: AllowList = .{};
    try parseAllowList(text[0..len], &list);
    try testing.expectEqual(@as(usize, max_helpers), list.len);
    const last = lookup(&list, "h31") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("/helper", last.path[0..last.path_len]);
    const extra = try std.fmt.bufPrint(text[len..], "extra 0:0 /helper\n", .{});
    len += extra.len;
    try testing.expectError(error.TooManyHelpers, parseAllowList(text[0..len], &list));
}

test "helpers: the line limit includes arguments but excludes the trailing newline" {
    try milestone.require(17);
    var text: [max_line_len + 2]u8 = @splat('a');
    const prefix = "long 0:0 /";
    @memcpy(text[0..prefix.len], prefix);
    text[max_line_len] = '\n';
    var list: AllowList = .{};
    try parseAllowList(text[0 .. max_line_len + 1], &list);
    const helper = lookup(&list, "long") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(usize, max_line_len - prefix.len + 1), helper.path_len);
    try testing.expectEqualStrings(text[prefix.len - 1 .. max_line_len], helper.path[0..helper.path_len]);
    text[max_line_len] = 'a';
    text[max_line_len + 1] = '\n';
    try testing.expectError(error.TooLong, parseAllowList(&text, &list));
    @memcpy(text[0.."long 0:0 /h ".len], "long 0:0 /h ");
    try testing.expectError(error.TooLong, parseAllowList(&text, &list));
}

test "helpers: OK and REFUSED replies have exact wire bytes" {
    try milestone.require(17);
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("HELPER initdb OK 42\n", try encodeReply("initdb", 42, &buf));
    try testing.expectEqualStrings("HELPER no-such-helper REFUSED\n", try encodeReply("no-such-helper", null, &buf));
    var exact: [19]u8 = undefined;
    try testing.expectEqualStrings("HELPER initdb OK 1\n", try encodeReply("initdb", 1, &exact));
}

test "helpers: maximum u32 pid and maximum name fit in a reply" {
    try milestone.require(17);
    var buf: [64]u8 = undefined;
    const name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try testing.expectEqualStrings(
        "HELPER " ++ name ++ " OK 4294967295\n",
        try encodeReply(name, std.math.maxInt(u32), &buf),
    );
}

test "helpers: a too-small reply buffer returns NoSpaceLeft" {
    try milestone.require(17);
    var tiny: [8]u8 = undefined;
    try testing.expectError(error.NoSpaceLeft, encodeReply("initdb", 42, &tiny));
    try testing.expectError(error.NoSpaceLeft, encodeReply("initdb", null, &tiny));
}
